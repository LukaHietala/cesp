package main

import (
	"encoding/json"
)

type Event struct {
	Type    string          `json:"e"`
	Payload json.RawMessage `json:"p,omitempty"`
}

type FSListResPayload struct {
	Files []string `json:"files"`
}

type DocPathPayload struct {
	Path string `json:"path"`
}

type DocOpenResPayload struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

type DocUpdatePayload struct {
	Path  string   `json:"path"`
	Range [2]int   `json:"range"` // [start_row, end_row]
	Lines []string `json:"lines"`
}

type CursorMovePayload struct {
	ID   string `json:"id,omitempty"`   // Added by server
	Name string `json:"name,omitempty"` // Added by server
	Path string `json:"path"`
	Pos  [2]int `json:"pos"` // [row, col]
}

type CursorRangePayload struct {
	ID    string `json:"id,omitempty"`   // Added by server
	Name  string `json:"name,omitempty"` // Added by server
	Path  string `json:"path"`
	Range [4]int `json:"range"` // [start_row, start_col, end_row, end_col]
}

type AuthHandshakePayload struct {
	Name string `json:"name"`
}

type UserPayload struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type ServerErrorPayload struct {
	Message string `json:"msg"`
}
