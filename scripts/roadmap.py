"""Write docs/roadmap.md from the GitHub milestones and issues.

Run from the repository root: python3 scripts/roadmap.py
Needs the GitHub CLI (gh), logged in with access to the repository.
"""
import json
import re
import subprocess

AFTER_V03 = [
	"Sync between your Macs through iCloud.",
	"An app for iPhone and iPad that reuses the `Domain`, `Storage`, and connector packages.",
	"Budgets and a dashboard.",
	"PDF account statements through FinTS.",
	"Standing orders, scheduled transfers, templates, and pasting bank details from the clipboard.",
	"Outbox, batch transfers, foreign currency transfers, and SEPA direct debits.",
	"Import and export extensions compatible with MoneyMoney, and AppleScript automation.",
	"Certificate pinning for bank servers.",
	"HBCI chip cards and key files.",
	"Printing and printable reports.",
]


def gh(path):
	out = subprocess.run(["gh", "api", path], capture_output=True, text=True, check=True)
	return json.loads(out.stdout)


repo = subprocess.run(["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
	capture_output=True, text=True, check=True).stdout.strip()
milestones = sorted(gh(f"repos/{repo}/milestones?state=all&per_page=100"), key=lambda m: m["title"])
issues = [i for i in gh(f"repos/{repo}/issues?state=all&per_page=100") if "pull_request" not in i]

lines = [
	"# Roadmap",
	"",
	"This page lists what ships in each release up to v0.3. Each row links to the GitHub issue that holds the scope and the definition of done. The issues are the source of truth. Run `python3 scripts/roadmap.py` to regenerate this page from them.",
	"",
]
for m in milestones:
	goal, _, done = m["description"].partition("\n\nDone when. ")
	lines += [f"## {m['title']}", "", goal, "", f"**Done when.** {done}", "",
		"| Issue | Labels | Depends on |", "|---|---|---|"]
	for i in sorted((i for i in issues if i["milestone"] and i["milestone"]["number"] == m["number"]), key=lambda i: i["number"]):
		labels = ", ".join(l["name"] for l in i["labels"])
		deps_section = (i["body"] or "").partition("## Depends on")[2]
		deps = ", ".join(re.findall(r"#\d+", deps_section)) or "None"
		lines.append(f"| [#{i['number']} {i['title']}]({i['html_url']}) | {labels} | {deps} |")
	lines.append("")
lines += ["## After v0.3", ""] + [f"- {item}" for item in AFTER_V03] + [""]

with open("docs/roadmap.md", "w") as f:
	f.write("\n".join(lines))
print(f"wrote docs/roadmap.md with {len(issues)} issues")
