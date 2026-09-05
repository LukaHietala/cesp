package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json/v2"
	"errors"
	"io"
	"sync"
)

// Protocol (Big-Endian):
// +-----------+-----------+-------------------+----------------+
// | M1 (0x0C) | M2 (0x0E) | Length (uint32)   | Payload (JSON) |
// +-----------+-----------+-------------------+----------------+
// | 0 byte    | 1 byte    | 2-5 byte (4 byte) | 6 byte ->10 MB |
// +-----------------------+------------------------------------+
// | Header Size (6 bytes) | <----------- Payload ------------> |
// +-----------------------+------------------------------------+

// No versioning to undermine backwards compatibility

const (
	MagicByte1     = 0x0C
	MagicByte2     = 0x0E
	HeaderSize     = 6
	MaxPayloadSize = 10 << 20 // 10 MB
)

var (
	ErrPayloadTooLarge = errors.New("payload size exceeds maximum limit")
	ErrInvalidMagic    = errors.New("invalid magic bytes")
)

var bufPool = sync.Pool{
	New: func() any {
		return bytes.NewBuffer(make([]byte, 0, 1024))
	},
}

func Encode(w io.Writer, v any) error {
	buf := bufPool.Get().(*bytes.Buffer)
	buf.Reset()

	defer func() {
		if buf.Cap() <= 64*1024 {
			bufPool.Put(buf)
		}
	}()

	buf.Write([]byte{0, 0, 0, 0, 0, 0})

	if err := json.MarshalWrite(buf, v); err != nil {
		return err
	}

	b := buf.Bytes()
	payloadLen := len(b) - HeaderSize
	if payloadLen > MaxPayloadSize {
		return ErrPayloadTooLarge
	}

	b[0] = MagicByte1
	b[1] = MagicByte2
	binary.BigEndian.PutUint32(b[2:6], uint32(payloadLen))

	_, err := w.Write(b)

	return err
}

func Decode(r io.Reader, v any) error {
	var header [HeaderSize]byte
	if _, err := io.ReadFull(r, header[:]); err != nil {
		return err
	}

	if header[0] != MagicByte1 || header[1] != MagicByte2 {
		return ErrInvalidMagic
	}

	payloadLen := binary.BigEndian.Uint32(header[2:6])
	if payloadLen > MaxPayloadSize {
		return ErrPayloadTooLarge
	}

	lr := io.LimitReader(r, int64(payloadLen))

	if err := json.UnmarshalRead(lr, v); err != nil {
		return err
	}

	// Drain unconsumed bytes
	_, _ = io.Copy(io.Discard, lr)

	return nil
}
