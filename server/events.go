package main

type UpdateChanges struct {
	First   int      `json:"first"`
	OldLast int      `json:"old_last"`
	Lines   []string `json:"lines"`
}

type EventUpdate struct {
	Event   string        `json:"event"`
	Changes UpdateChanges `json:"changes"`
}
