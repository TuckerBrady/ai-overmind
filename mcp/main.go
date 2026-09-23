// Command overmind-mcp serves an ai-overmind team root over the Model Context
// Protocol on stdio, so any MCP client can boot a seat and read the team's
// shared state without the Claude Code plugin.
//
//	overmind-mcp --root "C:\path\to\AI Team" [--seat T-Bot]
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"

	"github.com/TuckerBrady/ai-overmind/mcp/team"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// version is set at build time with -ldflags "-X main.version=...".
var version = "dev"

func main() {
	root := flag.String("root", os.Getenv("OVERMIND_ROOT"), "team root folder (default $OVERMIND_ROOT)")
	seat := flag.String("seat", os.Getenv("OVERMIND_SEAT"), "default seat for this client (default $OVERMIND_SEAT)")
	showVersion := flag.Bool("version", false, "print the version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Println("overmind-mcp", version)
		return
	}
	// stdout carries the protocol; every diagnostic goes to stderr.
	log.SetOutput(os.Stderr)

	t, err := team.Open(*root)
	if err != nil {
		log.Fatal(err)
	}
	if *seat != "" {
		if _, err := t.Seat(*seat); err != nil {
			log.Fatal(err)
		}
	}
	s, err := newServer(t, version, *seat)
	if err != nil {
		log.Fatal(err)
	}
	if err := s.Run(context.Background(), &mcp.StdioTransport{}); err != nil {
		log.Fatal(err)
	}
}
