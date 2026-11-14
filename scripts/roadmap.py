"""Write docs/roadmap.md from the OpenSpec changes and the GitHub milestones and issues.

Run from the repository root: python3 scripts/roadmap.py
Needs the GitHub CLI (gh), logged in with access to the repository.
"""
import json
import pathlib
import re
import subprocess

IDEAS = [
	"Sync between your Macs through iCloud.",
	"An app for iPhone and iPad that reuses the `Domain`, `Storage`, and connector packages.",
]


def gh(path):
	"""Return every item of a list endpoint. One page holds at most 100, and the repository has more issues and pull requests."""
	out = subprocess.run(["gh", "api", "--paginate", "--slurp", path], capture_output=True, text=True, check=True)
	return [item for page in json.loads(out.stdout) for item in page]


def read_changes():
	"""Return one record for each active change in openspec/changes."""
	changes = []
	for folder in sorted(pathlib.Path("openspec/changes").iterdir()):
		meta = folder / ".openspec.yaml"
		if folder.name == "archive" or not meta.exists():
			continue
		text = meta.read_text()
		milestone = re.search(r"^x-milestone:\s*(\S+)", text, re.M)
		issues = re.search(r"^x-issues:\s*\[(.*)\]", text, re.M)
		specs = sorted(folder.glob("specs/*/spec.md"))
		changes.append({
			"name": folder.name,
			"milestone": milestone[1] if milestone else "later",
			"issues": [int(n) for n in re.findall(r"\d+", issues[1])] if issues else [],
			"capabilities": [spec.parent.name for spec in specs],
			"requirements": sum(len(re.findall(r"^### Requirement:", spec.read_text(), re.M)) for spec in specs),
		})
	return changes


def change_rows(changes, repo, with_issues):
	rows = []
	for c in changes:
		cells = [f"[{c['name']}](../openspec/changes/{c['name']}/proposal.md)",
			", ".join(f"`{cap}`" for cap in c["capabilities"]), str(c["requirements"])]
		if with_issues:
			cells.append(", ".join(f"[#{n}](https://github.com/{repo}/issues/{n})" for n in c["issues"]) or "None")
		rows.append("| " + " | ".join(cells) + " |")
	return rows


repo = subprocess.run(["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
	capture_output=True, text=True, check=True).stdout.strip()
milestones = sorted(gh(f"repos/{repo}/milestones?state=all&per_page=100"), key=lambda m: m["title"])
issues = [i for i in gh(f"repos/{repo}/issues?state=open&per_page=100") if "pull_request" not in i]
changes = read_changes()

lines = [
	"# Roadmap",
	"",
	"This page lists what ships in each release. The specs in [openspec/changes](../openspec/changes/) define the behavior. The GitHub issues track the work. Run `python3 scripts/roadmap.py` to regenerate this page from both.",
	"",
	f"The project has {len(changes)} changes with {sum(c['requirements'] for c in changes)} requirements. A change leaves this page when its code is merged and the change is archived into [openspec/specs](../openspec/specs/).",
	"",
]
for m in milestones:
	key = m["title"].split()[0]
	goal, _, done = m["description"].partition("\n\nDone when. ")
	lines += [f"## {m['title']}", "", goal, "", f"**Done when.** {done}", "",
		"### Specs", "", "| Change | Capability | Requirements | Issues |", "|---|---|---|---|"]
	lines += change_rows([c for c in changes if c["milestone"] == key], repo, with_issues=True)
	lines += ["", "### Issues", "", "| Issue | Labels | Depends on |", "|---|---|---|"]
	for i in sorted((i for i in issues if i["milestone"] and i["milestone"]["number"] == m["number"]), key=lambda i: i["number"]):
		labels = ", ".join(l["name"] for l in i["labels"])
		deps_section = (i["body"] or "").partition("## Depends on")[2]
		deps = ", ".join(re.findall(r"#\d+", deps_section)) or "None"
		lines.append(f"| [#{i['number']} {i['title']}]({i['html_url']}) | {labels} | {deps} |")
	lines.append("")
lines += ["## Later", "", "These changes have a spec and no release yet.", "",
	"| Change | Capability | Requirements |", "|---|---|---|"]
lines += change_rows([c for c in changes if c["milestone"] == "later"], repo, with_issues=False)
lines += ["", "## Ideas without a spec", ""] + [f"- {item}" for item in IDEAS] + [""]

with open("docs/roadmap.md", "w") as f:
	f.write("\n".join(lines))
print(f"wrote docs/roadmap.md with {len(changes)} changes and {len(issues)} issues")
