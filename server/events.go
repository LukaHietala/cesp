package main

type EventMessage struct {
	Event   string   `json:"event"`
	Path    string   `json:"path,omitempty"`
	Changes *Changes `json:"changes,omitempty"`
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
