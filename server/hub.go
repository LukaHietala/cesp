package main

import (
	"net"
)

// Central place to manage all TCP connections
// Heavily used: https://github.com/gorilla/websocket/blob/main/examples/chat/hub.go

type Client struct {
	conn net.Conn
	send chan string
}

type Message struct {
	sender net.Conn
	event  string
}

type Hub struct {
	clients    map[*Client]bool
	broadcast  chan Message
	register   chan *Client
	unregister chan *Client
}

func NewHub() *Hub {
	return &Hub{
		clients:    make(map[*Client]bool),
		broadcast:  make(chan Message),
		register:   make(chan *Client),
		unregister: make(chan *Client),
	}
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.clients[client] = true

		case client := <-h.unregister:
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				close(client.send)
			}

		case msg := <-h.broadcast:
			for client := range h.clients {
				if client.conn == msg.sender {
					continue
				}

				select {
				case client.send <- msg.event:
				default:
					// Drop if send buffer full
					close(client.send)
					delete(h.clients, client)
				}
			}
		}
	}
}
