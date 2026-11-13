package calc

import "testing"

func TestSoma(t *testing.T) {
	if got := Soma(2, 3); got != 5 {
		t.Fatalf("Soma(2, 3) = %d; esperado 5", got)
	}
}
