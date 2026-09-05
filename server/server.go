package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net"
	"os"
	"strings"
	"time"
)

func NewServer(addr, rootDir string, ignoredDirs map[string]bool) *Server {
	s := &Server{
		quit: make(chan struct{}),
	}

	listener, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatal(err)
	}

	hub := NewHub()
	go hub.Run()

	fsys := os.DirFS(rootDir)

	session := &Session{
		fsys:        fsys,
		rootDir:     rootDir,
		ignoredDirs: ignoredDirs,
	}

	s.listener = listener
	s.hub = hub
	s.session = session

	s.wg.Add(1)
	go s.serve()

	return s
}

func (s *Server) Stop() {
	// Save all the buffers
	s.session.FlushAll()
	// Signals to all goroutines to die
	close(s.quit)
	// Stop accepting new connections
	s.listener.Close()
	// Closes all existing connections
	s.hub.Stop()
	// Wait for everything to cleanup
	s.wg.Wait()
}

func (s *Server) serve() {
	defer s.wg.Done()
	log.Println("listening on", s.listener.Addr().String())

	for {
		conn, err := s.listener.Accept()
		if err != nil {
			select {
			case <-s.quit:
				return
			default:
				log.Println("accept error", err)
			}
			continue
		}

		go s.handleConnection(conn)
	}
}

func (s *Server) handleConnection(conn net.Conn) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	client := NewClient(conn)

	s.hub.register <- client

	defer func() {
		s.hub.unregister <- client
		conn.Close()
		log.Println("connection closed", conn.RemoteAddr())
	}()

	log.Println("new connection", conn.RemoteAddr())

	go func() {
		ticker := time.NewTicker(60 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return

			case msg, ok := <-client.send:
				if !ok {
					return
				}
				conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
				if err := Encode(conn, msg); err != nil {
					log.Printf("encode error to %s: %v\n", conn.RemoteAddr(), err)
					conn.Close()
					cancel()
					return
				}

			case <-ticker.C:
				conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
				if err := Encode(conn, Event{Type: "server:ping"}); err != nil {
					log.Printf("ping error to %s: %v\n", conn.RemoteAddr(), err)
					conn.Close()
					cancel()
					return
				}
			}
		}
	}()

	// Read pump
	for {
		conn.SetReadDeadline(time.Now().Add(5 * time.Minute))
		var ev Event
		err := Decode(conn, &ev)
		if err != nil {
			if ctx.Err() != nil {
				break
			}
			if err != io.EOF {
				log.Printf("decode error from %s: %v\n", conn.RemoteAddr(), err)
			}
			break
		}

		log.Println("received event:", ev.Type)

		err = s.handleEvent(ev, client, conn)
		if err != nil {
			log.Printf("event error %s: %v\n", ev.Type, err)

			errorEv := Event{
				Type: "server:error",
				Payload: marshalPayload(ServerErrorPayload{
					Message: err.Error(),
				}),
			}
			select {
			case client.send <- errorEv:
			default:
			}
		}
	}
}

func marshalPayload(v any) json.RawMessage {
	b, err := json.Marshal(v)
	if err != nil {
		// Server should never try to send broken json
		panic(fmt.Errorf("failed to marshal payload: %v", err))
	}
	return b
}

func (s *Server) handleEvent(ev Event, client *Client, conn net.Conn) error {
	clientIDStr := fmt.Sprintf("%d", client.id)

	switch ev.Type {
	case "fs:list":
		files, err := getFiles(s.session.fsys, s.session.ignoredDirs)
		if err != nil {
			return err
		}

		client.send <- Event{
			Type:    "fs:list_res",
			Payload: marshalPayload(FSListResPayload{Files: files}),
		}

	case "doc:open":
		var p DocPathPayload
		if err := json.Unmarshal(ev.Payload, &p); err != nil {
			return err
		}

		b := s.session.GetBuffer(p.Path)
		lines, _ := b.GetLines(0, -1)

		client.send <- Event{
			Type: "doc:open_res",
			Payload: marshalPayload(DocOpenResPayload{
				Path:    p.Path,
				Content: strings.Join(lines, "\n"),
			}),
		}

	case "doc:update":
		var p DocUpdatePayload
		if err := json.Unmarshal(ev.Payload, &p); err != nil {
			return err
		}

		b := s.session.GetBuffer(p.Path)
		b.SetLines(p.Range[0], p.Range[1], p.Lines)

		s.hub.broadcast <- Message{
			sender:  conn,
			payload: ev,
		}

	case "doc:save":
		var p DocPathPayload
		if err := json.Unmarshal(ev.Payload, &p); err != nil {
			return err
		}

		b := s.session.GetBuffer(p.Path)
		if err := b.Save(s.session.rootDir); err != nil {
			log.Printf("error saving %s: %v\n", p.Path, err)
		} else {
			log.Printf("saved %s\n", p.Path)
		}

	case "auth:handshake":
		var p AuthHandshakePayload
		if err := json.Unmarshal(ev.Payload, &p); err != nil {
			return err
		}

		if err := client.SetName(p.Name); err != nil {
			return err
		}

		userPayload := marshalPayload(UserPayload{
			ID:   clientIDStr,
			Name: p.Name,
		})

		client.send <- Event{
			Type:    "auth:handshake_res",
			Payload: userPayload,
		}

		s.hub.broadcast <- Message{
			sender: conn,
			payload: Event{
				Type:    "user:join",
				Payload: userPayload,
			},
		}

	case "cursor:move":
		var p CursorMovePayload
		if err := json.Unmarshal(ev.Payload, &p); err != nil {
			return err
		}

		p.ID = clientIDStr
		p.Name = client.name
		ev.Payload = marshalPayload(p)

		s.hub.broadcast <- Message{
			sender:  conn,
			payload: ev,
		}

	case "cursor:range":
		var p CursorRangePayload
		if err := json.Unmarshal(ev.Payload, &p); err != nil {
			return err
		}

		p.ID = clientIDStr
		p.Name = client.name
		ev.Payload = marshalPayload(p)

		s.hub.broadcast <- Message{
			sender:  conn,
			payload: ev,
		}

	case "cursor:leave":
		userPayload := marshalPayload(UserPayload{
			ID:   clientIDStr,
			Name: client.name,
		})

		s.hub.broadcast <- Message{
			sender:  conn,
			payload: userPayload,
		}

	case "server:pong":
		return nil

	case "":
		return fmt.Errorf("empty event type")

	default:
		return fmt.Errorf("unknown event type: %s", ev.Type)
	}

	return nil
}

func getFiles(fsys fs.FS, ignoredDirs map[string]bool) ([]string, error) {
	var paths []string

	err := fs.WalkDir(fsys, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			if ignoredDirs[d.Name()] {
				return fs.SkipDir
			}
			return nil
		}

		paths = append(paths, path)
		return nil
	})

	return paths, err
}
