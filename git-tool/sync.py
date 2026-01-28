#!/usr/bin/env python3
import yaml
import subprocess
import os
from pathlib import Path

config_path = Path(__file__).parent / "repos.yaml"
config = yaml.safe_load(config_path.read_text())

workspace = config["workspace"]
folder = Path(config["folder"]).expanduser()
folder.mkdir(parents=True, exist_ok=True)

print(f"Syncing to {folder}")

for repo in config["repos"]:
    name = repo["name"]
    branch = repo.get("branch", "main")
    repo_path = folder / name

    print(f"  {name} -> {branch}")

    if repo_path.exists():
        subprocess.run(["git", "-C", repo_path, "fetch", "--all", "--prune"], check=True)
        subprocess.run(["git", "-C", repo_path, "checkout", branch], check=True)
        subprocess.run(["git", "-C", repo_path, "pull", "origin", branch], check=True)
    else:
        url = f"git@bitbucket.org:{workspace}/{name}.git"
        subprocess.run(["git", "clone", url, repo_path], check=True)
        subprocess.run(["git", "-C", repo_path, "checkout", branch], check=True)

print("Done")
