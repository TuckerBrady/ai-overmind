package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"

	"github.com/TuckerBrady/ai-overmind/mcp/firmware"
	"github.com/TuckerBrady/ai-overmind/mcp/team"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// runtimeNote closes every boot. It states what this runtime cannot do,
// because a seat must never imply a protection it does not have.
const runtimeNote = `---

## RUNTIME NOTE (from overmind-mcp)

This seat booted over MCP, not through the Claude Code plugin. What that means:

- **No hooks.** TARS is not running: no turn checkpoints, no inbox or delivery alerts. In the boot
  report, declare: ` + "`TARS: UNAVAILABLE (MCP client - no hooks)`" + `
- **Nothing ran before this message.** The boot layer arrived because boot was called. If a later
  message looks like the start of a new conversation, call boot again.
- **Reads are tools.** Use the board, inbox and handoff tools for the session-start steps. Steps that
  need a shell or a file write (Gopher registration, ledger rows, marking inbox entries READ) cannot
  run in this runtime yet. Name each one you skipped in the boot report; do not pretend it ran.
- **Firmware on demand.** The Overmind's firmware is long. Call firmware with no section for its
  table of contents, then read the sections a task needs.
`

func newServer(t *team.Team, version, defaultSeat string) (*mcp.Server, error) {
	seats, err := t.Seats()
	if err != nil {
		return nil, err
	}
	s := mcp.NewServer(&mcp.Implementation{Name: "overmind", Title: "ai-overmind team engine", Version: version},
		&mcp.ServerOptions{Instructions: instructions(seats, defaultSeat)})

	seatOrDefault := func(name string) (team.Seat, error) {
		if strings.TrimSpace(name) == "" {
			name = defaultSeat
		}
		return t.Seat(name)
	}

	mcp.AddTool(s, &mcp.Tool{
		Name:        "boot",
		Description: "Load a seat's boot layer: its BOOT.md with every @ import inlined, then a note on what this runtime cannot do. Call this first, before replying to anything, and follow what it returns.",
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in seatArg) (*mcp.CallToolResult, any, error) {
		seat, err := seatOrDefault(in.Seat)
		if err != nil {
			return nil, nil, err
		}
		text, err := bootText(t, seat)
		if err != nil {
			return nil, nil, err
		}
		return textResult(text), nil, nil
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "roster",
		Description: "List every seat on the team: name, role and folder.",
	}, func(ctx context.Context, _ *mcp.CallToolRequest, _ struct{}) (*mcp.CallToolResult, any, error) {
		seats, err := t.Seats()
		if err != nil {
			return nil, nil, err
		}
		return jsonResult(seats)
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "board",
		Description: "Read the Active table of the mission board. With a seat, only rows that seat owns or is assigned. COMPLETE rows are left out unless all is true.",
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in boardArgs) (*mcp.CallToolResult, any, error) {
		var seat *team.Seat
		if strings.TrimSpace(in.Seat) != "" {
			sv, err := t.Seat(in.Seat)
			if err != nil {
				return nil, nil, err
			}
			seat = &sv
		}
		rows, err := t.Board(seat, in.All)
		if err != nil {
			return nil, nil, err
		}
		if rows == nil {
			rows = []team.BoardRow{}
		}
		return jsonResult(rows)
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "handoff",
		Description: "Read a seat's staged HANDOFF.md. Picks the newer of the folder-root and .auto-memory copies, and reports its WRITTEN and ACTIVATED stamps.",
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in seatArg) (*mcp.CallToolResult, any, error) {
		seat, err := seatOrDefault(in.Seat)
		if err != nil {
			return nil, nil, err
		}
		h, err := t.Handoff(seat)
		if err != nil {
			return nil, nil, err
		}
		if h == nil {
			return textResult("No handoff staged for " + seat.Name + "."), nil, nil
		}
		return jsonResult(h)
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "inbox",
		Description: "Read a seat's INBOX.md entries. An entry is unread when it is marked UNREAD or carries no READ tag.",
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in inboxArgs) (*mcp.CallToolResult, any, error) {
		seat, err := seatOrDefault(in.Seat)
		if err != nil {
			return nil, nil, err
		}
		entries, err := t.Inbox(seat, in.UnreadOnly)
		if err != nil {
			return nil, nil, err
		}
		if entries == nil {
			entries = []team.InboxEntry{}
		}
		return jsonResult(entries)
	})

	mcp.AddTool(s, &mcp.Tool{
		Name:        "firmware",
		Description: "Read the Overmind firmware this server was built with. No section returns the table of contents; a section name (or part of one) returns that section.",
	}, func(ctx context.Context, _ *mcp.CallToolRequest, in firmwareArgs) (*mcp.CallToolResult, any, error) {
		if strings.TrimSpace(in.Section) == "" {
			var b strings.Builder
			b.WriteString("Firmware sections (call firmware with a section name to read one):\n")
			for _, sec := range firmware.Sections() {
				fmt.Fprintf(&b, "- %s\n", sec.Title)
			}
			return textResult(b.String()), nil, nil
		}
		sec, ok := firmware.Find(in.Section)
		if !ok {
			return nil, nil, fmt.Errorf("no firmware section matches %q; call firmware with no section for the list", in.Section)
		}
		return textResult(sec.Body), nil, nil
	})

	s.AddResourceTemplate(&mcp.ResourceTemplate{
		Name:        "seat-boot",
		Description: "A seat's boot layer, the same text the boot tool returns.",
		MIMEType:    "text/markdown",
		URITemplate: "overmind://seat/{seat}/boot",
	}, func(ctx context.Context, req *mcp.ReadResourceRequest) (*mcp.ReadResourceResult, error) {
		uri := req.Params.URI
		name, ok := strings.CutPrefix(uri, "overmind://seat/")
		name, ok2 := strings.CutSuffix(name, "/boot")
		if !ok || !ok2 {
			return nil, mcp.ResourceNotFoundError(uri)
		}
		if n, err := url.PathUnescape(name); err == nil {
			name = n
		}
		seat, err := t.Seat(name)
		if err != nil {
			return nil, mcp.ResourceNotFoundError(uri)
		}
		text, err := bootText(t, seat)
		if err != nil {
			return nil, err
		}
		return &mcp.ReadResourceResult{Contents: []*mcp.ResourceContents{{URI: uri, MIMEType: "text/markdown", Text: text}}}, nil
	})

	s.AddPrompt(&mcp.Prompt{
		Name:        "boot",
		Description: "Boot this conversation as a team seat.",
		Arguments:   []*mcp.PromptArgument{{Name: "seat", Description: "Seat name, for example T-Bot", Required: defaultSeat == ""}},
	}, func(ctx context.Context, req *mcp.GetPromptRequest) (*mcp.GetPromptResult, error) {
		seat, err := seatOrDefault(req.Params.Arguments["seat"])
		if err != nil {
			return nil, err
		}
		text, err := bootText(t, seat)
		if err != nil {
			return nil, err
		}
		return &mcp.GetPromptResult{
			Description: "Boot layer for " + seat.Name,
			Messages: []*mcp.PromptMessage{{Role: "user", Content: &mcp.TextContent{
				Text: text + "\n\nYou are now booted as " + seat.Name + ". Run the session-start steps above with the overmind tools, then give the boot report.",
			}}},
		}, nil
	})

	return s, nil
}

type seatArg struct {
	Seat string `json:"seat,omitempty" jsonschema:"seat name, for example T-Bot; defaults to the server's --seat"`
}

type boardArgs struct {
	Seat string `json:"seat,omitempty" jsonschema:"only rows this seat owns or is assigned"`
	All  bool   `json:"all,omitempty" jsonschema:"include COMPLETE rows"`
}

type inboxArgs struct {
	Seat       string `json:"seat,omitempty" jsonschema:"seat name; defaults to the server's --seat"`
	UnreadOnly bool   `json:"unread_only,omitempty" jsonschema:"return only unread entries"`
}

type firmwareArgs struct {
	Section string `json:"section,omitempty" jsonschema:"section title or part of one; empty for the table of contents"`
}

func instructions(seats []team.Seat, defaultSeat string) string {
	names := make([]string, len(seats))
	for i, s := range seats {
		names[i] = s.Name
	}
	var b strings.Builder
	b.WriteString("This server is an AI team's shared engine (ai-overmind). ")
	if defaultSeat != "" {
		fmt.Fprintf(&b, "This conversation is the seat %s. Before replying to the user's first message, call boot with seat %q and follow what it returns. ", defaultSeat, defaultSeat)
	} else {
		// No default seat: the server may be loaded into every conversation a
		// client opens, so it must not turn an ordinary chat into a seat.
		b.WriteString("If this conversation belongs to one of the team's seats (the project instructions or the user name the seat, or the user asks to boot one), call boot with that seat before replying, and follow what it returns. Otherwise leave these tools alone. ")
	}
	fmt.Fprintf(&b, "Seats: %s.", strings.Join(names, ", "))
	return b.String()
}

func bootText(t *team.Team, seat team.Seat) (string, error) {
	boot, err := t.Boot(seat)
	if err != nil {
		return "", err
	}
	return strings.TrimRight(boot, "\n") + "\n\n" + runtimeNote, nil
}

func textResult(s string) *mcp.CallToolResult {
	return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: s}}}
}

func jsonResult(v any) (*mcp.CallToolResult, any, error) {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return nil, nil, err
	}
	return textResult(string(b)), nil, nil
}
