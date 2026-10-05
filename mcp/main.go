// Command overmind-mcp serves an ai-overmind team root over the Model Context
// Protocol on stdio, so any MCP client can boot a seat and read the team's
// shared state without the Claude Code plugin.
//
//	overmind-mcp --root "C:\path\to\AI Team" [--seat T-Bot] [--plugin-root DIR]
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"

	"github.com/TuckerBrady/ai-overmind/mcp/team"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// version is set at build time with -ldflags "-X main.version=...".
var version = "dev"

func main() {
	// stdout carries the protocol; every diagnostic goes to stderr.
	log.SetOutput(os.Stderr)
	if err := run(context.Background(), os.Args[1:], os.Stdout, &mcp.StdioTransport{}); err != nil {
		log.Fatal(err)
	}
}

// run parses the flags, opens the team and serves it on tr until the client
// disconnects.
func run(ctx context.Context, args []string, out io.Writer, tr mcp.Transport) error {
	fs := flag.NewFlagSet("overmind-mcp", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	root := fs.String("root", os.Getenv("OVERMIND_ROOT"), "team root folder (default $OVERMIND_ROOT)")
	seat := fs.String("seat", os.Getenv("OVERMIND_SEAT"), "default seat for this client (default $OVERMIND_SEAT)")
	pluginRoot := fs.String("plugin-root", os.Getenv("OVERMIND_PLUGIN_ROOT"),
		"installed ai-overmind plugin folder; boot warns when its firmware differs from this server's (default $OVERMIND_PLUGIN_ROOT)")
	showVersion := fs.Bool("version", false, "print the version and exit")
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if *showVersion {
		fmt.Fprintln(out, "overmind-mcp", version)
		return nil
	}

	t, err := team.Open(*root)
	if err != nil {
		return err
	}
	if *seat != "" {
		if _, err := t.Seat(*seat); err != nil {
			return err
		}
	}
	s, err := newServer(t, config{version: version, defaultSeat: *seat, pluginRoot: *pluginRoot})
	if err != nil {
		return err
	}
	return s.Run(ctx, tr)
}
