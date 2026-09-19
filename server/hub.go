package main

import (
	"fmt"
	"net"
	"strconv"
	"sync/atomic"
)

// Central place to manage all TCP connections
// Heavily inspired by: https://github.com/gorilla/websocket/blob/main/examples/chat/hub.go

var nextID atomic.Uint64

type Client struct {
	id   uint64
	name string
	conn net.Conn
	send chan Event
}

type Message struct {
	sender  *Client
	payload Event
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
	quit chan struct{}
}

func NewClient(conn net.Conn) *Client {
	return &Client{
		id:   nextID.Add(1),
		conn: conn,
		send: make(chan Event, 100),
	}
}

func NewHub() *Hub {
	return &Hub{
		clients:    make(map[*Client]bool),
		broadcast:  make(chan Message, 256),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		quit:       make(chan struct{}),
	}
}

func (c *Client) Name() string {
	return c.name
}

func (c *Client) SetName(name string) error {
	if name == "" {
		return fmt.Errorf("name cannot be empty")
	}
	c.name = name
	return nil
}

// Cleanup all clients
func (h *Hub) Close() {
	close(h.quit)
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.clients[client] = true
		case client := <-h.unregister:
			if _, ok := h.clients[client]; ok {
				h.removeClient(client)

				if client.name != "" {
					continue
				}

				h.broadcastEvent(client, Event{
					Type: "user:leave",
					Payload: marshalPayload(UserPayload{
						ID:   strconv.FormatUint(client.id, 10),
						Name: client.name,
					}),
				})
			}

		case msg := <-h.broadcast:
			h.broadcastEvent(msg.sender, msg.payload)

		case <-h.quit:
			for client := range h.clients {
				h.removeClient(client)
			}
			return
		}
	}
}

func (h *Hub) broadcastEvent(sender *Client, payload Event) {
	for client := range h.clients {
		if client == sender {
			continue
		}

		select {
		case client.send <- payload:
		default:
			h.removeClient(client)
		}
	}
}

func (h *Hub) removeClient(c *Client) {
	c.conn.Close()
	close(c.send)
	delete(h.clients, c)
}
