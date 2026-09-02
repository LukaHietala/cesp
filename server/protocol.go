package main

import (
	"encoding/binary"
	"encoding/json/v2"
	"errors"
	"io"
	"net"
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

func Encode(w io.Writer, v any) error {
	// TODO: MarshalWrite, sync pool to recyle memory
	payload, err := json.Marshal(v)
	if err != nil {
		return err
	}

	payloadLen := len(payload)
	if payloadLen > MaxPayloadSize {
		return ErrPayloadTooLarge
	}

	var header [HeaderSize]byte
	header[0] = MagicByte1
	header[1] = MagicByte2
	binary.BigEndian.PutUint32(header[2:6], uint32(payloadLen))

	buffers := net.Buffers{header[:], payload}
	_, err = buffers.WriteTo(w)
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
