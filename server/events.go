package main

type EventMessage struct {
	Event    string        `json:"event"`
	Path     string        `json:"path,omitempty"`
	Changes  UpdateChanges `json:"changes"`
	Position []int         `json:"position,omitempty"` // cursor_move: [row, col]
	Name     string        `json:"name,omitempty"`     // cursor_move: name
}

type UpdateChanges struct {
	First   int      `json:"first"`
	OldLast int      `json:"old_last"`
	Lines   []string `json:"lines"`
}

// "request_files" event
type ResponseFiles struct {
	Event string   `json:"event"`
	Files []string `json:"files"`
}

// "request_file" event
type ResponseFile struct {
	Event   string `json:"event"`
	Path    string `json:"path"`
	Content string `json:"content"`
}
