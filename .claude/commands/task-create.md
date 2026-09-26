---
name: task-create
description: "Add a task to Savia's todo list. Usage: /task-create Investigate this site..."
argument-hint: "<description of the task>"
allowed-tools: [TaskCreate]
model_tier: fast
tier: core
---

Create a task from the user's input. The full text after `/task-create` is the task.

1. Use `$ARGUMENTS` as the task subject (first 80 chars) and full description
2. Create it via TaskCreate
3. Confirm: "Task #N created: {subject}"

If no arguments provided, ask the user what task to create.
