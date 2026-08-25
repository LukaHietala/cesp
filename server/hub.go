package main

import (
	"fmt"
	"net"
	"sync/atomic"
)

// Central place to manage all TCP connections
// Heavily inspired by: https://github.com/gorilla/websocket/blob/main/examples/chat/hub.go

var nextID atomic.Uint64

type Client struct {
	id   uint64
	name string
	conn net.Conn
	// Queue for outgoing messages (buffered)
	send chan any
}

type Message struct {
	sender  net.Conn
	payload any
}

type Hub struct {
	// List of connected cliens
	clients map[*Client]bool
	// Messages to broadcast
	broadcast chan Message
	// Register a new client
	register chan *Client
	// Unregister a new client
	unregister chan *Client
	// Signals hub to tear down
	shutdown chan struct{}
}

func NewClient(conn net.Conn) *Client {
	return &Client{
		id:   nextID.Add(1),
		conn: conn,
		send: make(chan any, 100),
	}
}

func NewHub() *Hub {
	return &Hub{
		clients:    make(map[*Client]bool),
		broadcast:  make(chan Message),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		shutdown:   make(chan struct{}),
	}
}

func (c *Client) SetName(name string) error {
	if name == "" {
		return fmt.Errorf("name cannot be empty")
	}
	c.name = name
	return nil
}

// Cleanup all clients
func (h *Hub) Stop() {
	close(h.shutdown)
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.clients[client] = true

		case client := <-h.unregister:
			h.broadcast <- Message{
				sender: nil,
				payload: UserJoinedOrLeft{
					Event: "user_left",
					ID:    client.id,
					Name:  client.name,
				}}
			delete(h.clients, client)

		case msg := <-h.broadcast:
			for client := range h.clients {
				if client.conn == msg.sender {
					continue
				}

				select {
				case client.send <- msg.payload:
				default:
					// Send buffer full, drop the client
					client.conn.Close()
					delete(h.clients, client)
				}
			}

		case <-h.shutdown:
			// Closes all connections, pumps will break cleanly
			for client := range h.clients {
				client.conn.Close()
			}
			return
		}
	}
}
