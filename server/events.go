package main

type EventMessage struct {
	Event     string     `json:"event"`
	FromID    uint64     `json:"from_id,omitempty"`
	Path      string     `json:"path,omitempty"`
	Name      string     `json:"name,omitempty"`
	Changes   *Changes   `json:"changes,omitempty"`
	Position  []int      `json:"position,omitempty"`
	Selection *Selection `json:"selection,omitempty"`
}

type Selection struct {
	StartPos []int `json:"start_pos"`
	// Regular pos is used as end :)
}

type Changes struct {
	First   int      `json:"first"`
	OldLast int      `json:"old_last"`
	Lines   []string `json:"lines"`
}

type ResponseFiles struct {
	Event string   `json:"event"`
	Files []string `json:"files"`
}

type ResponseFile struct {
	Event   string `json:"event"`
	Path    string `json:"path"`
	Content string `json:"content"`
}

type HandshakeReponse struct {
	Event string `json:"event"`
	Name  string `json:"name"`
	ID    uint64 `json:"id"`
}

type UserJoinedOrLeft struct {
	Event string `json:"event"`
	Name  string `json:"name"`
	ID    uint64 `json:"id"`
}
