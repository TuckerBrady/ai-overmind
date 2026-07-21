# Connectors

## How tool references work

Plugin files use `~~category` as a placeholder for whatever connector the human
has available. The Overmind is connector-agnostic — it describes plugin flows
in terms of `~~category` rather than specific products or tools.

## Categories used in this plugin

| Category           | Placeholder      | Included options                                       |
| ------------------- | ----------------- | ------------------------------------------------------- |
| Directory service   | `~~directory`     | Microsoft Teams, Outlook, Google Workspace, LDAP, Okta  |

## What the directory connector does

The Overmind uses `~~directory` during activation to look up the human's full
name, title, department, manager, and team — so it can introduce itself like a
colleague who already did their homework, and propose a team tuned to their
actual role.

**If no `~~directory` is connected**, the Overmind falls back gracefully: it
asks the human directly about their role, team, and what fills their days. The
experience is slightly less magic but fully functional.

## Connecting a directory service

Connecting a directory service (Teams, Outlook, Google Workspace) gives the
Overmind its baseline first impression.
