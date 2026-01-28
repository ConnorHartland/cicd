#!/usr/bin/env python3
import yaml
import subprocess
import os
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
CONFIG_FILE = SCRIPT_DIR / "repos.yaml"

def run(cmd, cwd=None):
    print(f"    $ {cmd}")
    subprocess.run(cmd, shell=True, cwd=cwd, check=True)

def main():
    with open(CONFIG_FILE) as f:
        config = yaml.safe_load(f)

    settings = config["settings"]
    workspace = settings["workspace"]
    base_path = Path(settings["base_path"]).expanduser()
    default_branch = settings.get("default_branch", "main")

    print("=== Git Repo Sync Tool ===")
    print(f"Workspace: {workspace}")
    print(f"Base path: {base_path}")
    print()

    for group_name, group in config["groups"].items():
        folder = group["folder"]
        full_path = base_path / folder

        print(f"--- {group_name} ---")
        print(f"Folder: {full_path}")

        full_path.mkdir(parents=True, exist_ok=True)

        for repo in group.get("repos", []):
            repo_name = repo["name"]
            branch = repo.get("branch", default_branch)
            repo_path = full_path / repo_name
            repo_url = f"git@bitbucket.org:{workspace}/{repo_name}.git"

            print()
            print(f"  {repo_name} -> {branch}")

            if repo_path.exists():
                print("    Fetching and switching branch...")
                run("git fetch --all --prune", cwd=repo_path)
                run(f"git checkout {branch}", cwd=repo_path)
                run(f"git pull origin {branch}", cwd=repo_path)
            else:
                print("    Cloning...")
                run(f"git clone {repo_url} {repo_path}")
                run(f"git checkout {branch}", cwd=repo_path)

        print()

    print("=== Sync complete ===")

if __name__ == "__main__":
    main()
