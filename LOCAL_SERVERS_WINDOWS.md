# Local servers (Windows) — Kyle & collaborators

You only need this if you are **testing the game on your PC with Godot**.  
If you just play at **https://play.arkenelle.com**, you do **not** need local servers.

## 1. One-time setup

1. Install **Git for Windows**: https://git-scm.com/download/win  
2. Install **Godot 4.7** (same major version as the project).  
3. Open **PowerShell** and clone the game once:

```powershell
cd $HOME\Documents
git clone https://github.com/kjp403/RealmCraft.git
cd RealmCraft
```

That creates: `C:\Users\<you>\Documents\RealmCraft`

4. **Required before servers will work:** open the project in the Godot editor once:
   - Open `Documents\RealmCraft\project.godot`
   - Wait until Godot finishes scanning/importing (bottom status bar idle)
   - Menu: **Project → Reload Current Project**, wait again
   - Confirm this file exists: `Documents\RealmCraft\.godot\global_script_class_cache.cfg`  
     (If it’s missing, servers will fail with confusing `GameMode not declared` spam.)

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
