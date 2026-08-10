# Local servers (Windows) — Kyle & collaborators

You only need this if you are **testing the game on your PC with Godot**.  
If you just play at **https://play.arkenelle.com**, you do **not** need local servers.

## 1. One-time setup

1. Install **Git for Windows**: https://git-scm.com/download/win  
2. Install **Godot 4.7** (same major version as the project) and make sure the `godot` command works in a terminal, **or** edit `Restart-LocalServers.ps1` and set `$GodotExe` to your Godot `.exe` path.  
3. Open **PowerShell** and clone the game once:

```powershell
cd $HOME\Documents
git clone https://github.com/kjp403/RealmCraft.git
cd RealmCraft
```

That creates: `C:\Users\<you>\Documents\RealmCraft`

## 2. Restart local servers (easy way)

1. Open the `RealmCraft` folder in File Explorer.  
2. Double-click **`Restart-LocalServers.bat`**  
3. Leave the three server windows open.  
4. Start the game client (Godot → open this project → run client), or from PowerShell inside the repo:

```powershell
godot --path . --mode=client
```

## 3. Update to latest code (before restarting)

```powershell
cd $HOME\Documents\RealmCraft
git checkout main
git pull
```

Then double-click `Restart-LocalServers.bat` again.

## Friend setup

Same steps: clone the repo, install Godot, double-click `Restart-LocalServers.bat`.  
They also need **GitHub access** to the repo if it is private (Kyle invites them as collaborator).
