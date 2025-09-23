package internal

type SafeError interface {
	error
	SafeMessage() string
}
