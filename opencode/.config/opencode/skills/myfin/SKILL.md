---
name: myfin
description: >
  Personal finance CLI tool. Use for tracking expenses, income, accounts,
  categories, tags, and generating financial reports. Triggers: expenses,
  income, budget, finance, accounts, credit cards, financial reports,
  ~/.myfin/, ~/.myfin.yaml
---

# myfin Skill

Manage personal finances using the myfin CLI tool.

## When This Skill MUST Be Used

**ALWAYS invoke this skill when the user mentions:**

- Adding or tracking expenses/income
- Managing financial accounts
- Setting up categories or tags for expenses
- Tracking credit card purchases (especially installments)
- Generating financial reports (balances, entries)
- Editing files in `~/.myfin/` or `~/.myfin.yaml`

**If you need to record, report, or analyze financial data, use this skill.**

## Data Locations

| Path | Purpose |
|------|---------|
| `~/.myfin.yaml` | Main config file (default currency, storage driver) |
| `~/.myfin/data/` | YAML storage (accounts, categories, entries, tags) |
| `~/.myfin/databases/` | SQLite databases (alternative storage) |

## Commands Reference

### Setup Commands

```bash
# Add a new account
myfin add account <name>

# Add a category (per-account)
myfin add category <name> --account <account> --type <inc|exp> --alias <alias> [--emoji <emoji>]

# Add a tag (global)
myfin add tag <name>

# Add a credit card
myfin add credit-card <name> --closing-day <n> --due-day <n>
```

### Entry Commands

```bash
# Add an expense
myfin add expense [amount] --account <name> --date <DD-MM-YY> --description <text> \
    [--category <name>] [--tags <tag1,tag2>] [--credit-card <name>] [--times <n>]

# Add an income
myfin add income [amount] --account <name> --date <DD-MM-YY> --description <text> \
    [--category <name>] [--tags <tag1,tag2>]
```

### Report Commands

```bash
# List all registered tags
myfin list tags

# Show entries with filters
myfin report entries [--from DD-MM-YY] [--until DD-MM-YY] \
    [--account <name>] [--filter-tags <tags>] [--filter-categories <cats>] \
    [--format table|md]

# Show account balances
myfin report balances [--account <name>] [--from DD-MM-YY] [--until DD-MM-YY] \
    [--format table|md]
```

### Global Flag

```bash
# Use a specific database
myfin --db <name> <command>
```

## Common Workflows

### Starting Fresh

```bash
# 1. Create an account
myfin add account personal

# 2. Add categories for the account
myfin add category food --account personal --type exp --alias food --emoji 🍕
myfin add category salary --account personal --type inc --alias salary --emoji 💰

# 3. Add tags (global, shared across accounts)
myfin add tag essential
myfin add tag leisure
```

### Recording Daily Expenses

```bash
# Simple expense
myfin add expense 50 --account personal --date 22-03-24 --description "groceries"

# Expense with category and tags
myfin add expense 100 --account personal --date 22-03-24 \
    --category food --tags essential,groceries \
    --description "weekly groceries"

# Credit card purchase in 3 installments
myfin add expense 300 --account personal --date 22-03-24 \
    --credit-card "MyCard" --times 3 \
    --description "new phone"
```

### Recording Income

```bash
myfin add income 5000 --account personal --date 01-03-24 \
    --category salary --description "monthly salary"
```

### End-of-Month Reports

```bash
# View all entries for March 2024
myfin report entries --from 01-03-24 --until 31-03-24 --format md

# View balance for a specific account
myfin report balances --account personal --from 01-03-24 --until 31-03-24
```

## Validation Rules

The use case layer validates:

- **Categories**: Must exist and belong to the account (use name or alias)
- **Tags**: Must be pre-registered (use `myfin add tag <name>` first)
- **Credit cards**: Must exist (use `myfin add credit-card` first)
- **Installments** (`--times`): Required when using `--credit-card`

## Error Messages

| Error | Solution |
|-------|----------|
| `account not found: <name>` | Run `myfin add account <name>` |
| `category not found` | Run `myfin add category <name> --account <acc> --type <inc|exp> --alias <alias>` |
| `tag not registered: <name>` | Run `myfin add tag <name>` |
| `credit card not found: <name>` | Run `myfin add credit-card <name> --closing-day <n> --due-day <n>` |
| `--times is required when using --credit-card` | Add `--times <n>` to split into installments |

## Tips

1. **Tags are global** - Create them once, use across all accounts
2. **Categories are per-account** - Each account has its own categories
3. **Use `--format md` for markdown output** - Useful for exporting reports
4. **Date formats accepted**: `DD-MM-YY` (e.g., `22-03-24`)
