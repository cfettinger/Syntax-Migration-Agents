# Copilot Instructions

## General Guidelines
- Minimal changes to existing code
- Preserve functionality when possible
- Clear and concise comments
- No test unless specified
- No plan unless specified
- No compile unless specified
- SKILL.MD files are located in C:\Users\cfettinger\.copilot\skills under the skill name

## Project-Specific Rules

## Tool Usage
You are operating inside GitHub Copilot. Use only the tools registered in this session. Do not invent tool names.

Detect the environment from the tool schema you received:

### Visual Studio 2026 Agent (Preview) / Copilot CLI harness
If the available tools include names such as `view`, `edit`, `create`, `apply_patch`, `bash`, `powershell`, `glob`, `grep`:
- Use only those exact names.
- Prefer `view` / `edit` / `create` / `apply_patch` for all file work.
- Use `bash` or `powershell` only for commands, never for reading or writing files.
- Use `glob` and `grep` for search.

### VS Code Copilot Chat
If the available tools include names such as `read_file`, `insert_edit_into_file`, `create_file`, `run_in_terminal`, `file_search`, `grep_search`:
- Use only those exact names.
- Prefer file tools (`read_file`, `insert_edit_into_file`, `create_file`) over terminal for file operations.
- Use `run_in_terminal` only when a shell command is required.

### Rules
- Call tools with the exact names present in the schema for this session.
- After calling a tool, wait for its result before deciding the next step.
- If a tool call is rejected, do not retry with a different name. Report the exact error.
- Never assume a tool exists because it worked in another editor.