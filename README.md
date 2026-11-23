# Minecraft Survival Server Setup Guide

This guide is for building and operating a Java-and-Bedrock survival server on an Oracle Cloud Ampere A1 Ubuntu instance. It is intended to be followed in order, checking each stage before moving to the next.

## Target setup

- **Host:** Oracle Cloud Ampere A1, ARM64, 2 OCPUs, 12 GB RAM, Ubuntu
- **Server memory:** 4 GB Java heap; leave the remaining memory for Ubuntu and file caching
- **Server software:** Paper, with the requested target written as “26.3”
- **Java players:** Paper, with ViaVersion and ViaBackwards for the compatible client versions
- **Bedrock players:** Geyser and Floodgate
- **Gameplay:** EssentialsX, LuckPerms, Vault for chat integration, GriefPrevention, and optionally Chunky
- **World rule:** `keepInventory=true`, if this is still the desired rule

### Version compatibility is a required first check

Before downloading anything, identify the exact Minecraft game version and Paper build meant by “Paper 26.3.” Check that the selected Paper build, Java runtime, Geyser, Floodgate, ViaVersion, ViaBackwards, and every other plugin support one another. Use the official download pages and compatibility notes for the exact versions. Do not assume “all versions” means every Java or Bedrock release: Geyser and the Via* plugins each have supported ranges.

Record the chosen versions in a small deployment note before installing them. Pin versions during initial setup; update deliberately after making a backup.

## Important separation: this GitHub project and the live server

Keep this guide and other safe templates in the GitHub project. Keep the live server, world files, plugin JARs, generated configuration, logs, and Floodgate private key in the server's runtime directory on Ubuntu. Do not upload a live world, plugin binaries, passwords, private keys, or a full server directory to a public repository.

The commands below use `/opt/minecraft/server` for the live server. They do not install the live server into this documentation project.

## Step-by-step setup

### 1. Confirm the Oracle instance and version choices

- In the Oracle Cloud console, confirm the instance shape, 2 OCPUs, 12 GB memory, Ubuntu release, public IP, and ARM64 architecture.
- Confirm SSH access and ensure you can log in before changing firewall settings.
- Resolve what “Paper 26.3” means by checking the official Paper downloads for the intended Minecraft release and build.
- Check the Java requirement stated for that Paper build. Check supported versions for Geyser, Floodgate, ViaVersion, ViaBackwards, EssentialsX, LuckPerms, Vault, GriefPrevention, and Chunky.
- Write down the exact Minecraft, Paper, Java, and plugin versions. If a required plugin does not support the chosen Paper release, stop and choose a compatible combination before continuing.

### 2. Open only the required Oracle Cloud network ports

In the instance's Virtual Cloud Network security rules (and any Network Security Group attached to it), allow:

| Purpose | Protocol | Port | Source |
|---|---|---:|---|
| SSH administration | TCP | 22 | Your IP address or trusted network only |
| Java Minecraft | TCP | 25565 | Players, or the intended public range |
| Bedrock Minecraft | UDP | 19132 | Players, or the intended public range |

Do not open RCON. It is disabled in this plan. Keep SSH restricted; do not expose it to all addresses unless you knowingly accept that risk.

### 3. Update Ubuntu and create a dedicated server account

Log in over SSH, then update the operating system:

```bash
sudo apt update
sudo apt upgrade
```

Create a system account and the live-server and backup directories:

```bash
sudo useradd --system --create-home --home-dir /opt/minecraft --shell /usr/sbin/nologin minecraft
sudo install -d -o minecraft -g minecraft -m 750 /opt/minecraft/server
sudo install -d -o minecraft -g minecraft -m 750 /opt/minecraft/backups
```

If the `minecraft` account already exists, inspect it rather than running `useradd` again. The server process should run as this account, not as `root`.

### 4. Install the Java version required by the selected Paper build

Use the Java version confirmed in Step 1 and available for the Ubuntu release and ARM64 architecture. For example, replace `<required-java-version>` with the actual version number:

```bash
sudo apt install openjdk-<required-java-version>-jre-headless
java -version
```

Confirm that the reported version is the one Paper requires before proceeding.

### 5. Configure the Ubuntu firewall

Only do this after confirming SSH is working and the Oracle Cloud rules are in place. If UFW is already configured, inspect its current rules before changing them.

```bash
sudo ufw allow from <your-trusted-ip> to any port 22 proto tcp
sudo ufw allow 25565/tcp
sudo ufw allow 19132/udp
sudo ufw status
```

Replace `<your-trusted-ip>` with your actual trusted SSH source. If enabling UFW for the first time, make sure the SSH allow rule is correct before enabling it, or you could lock yourself out. Do not add a TCP rule for Bedrock's UDP port.

After confirming the SSH rule is correct, enable UFW if it is not already enabled:

```bash
sudo ufw enable
```

### 6. Install Paper and complete its first start

- Download the Paper JAR for the exact build confirmed in Step 1, using Paper's official download source.
- Place it at `/opt/minecraft/server/paper.jar` and set ownership:

```bash
sudo chown minecraft:minecraft /opt/minecraft/server/paper.jar
```

- Start Paper once as the `minecraft` user so it generates its initial files:

```bash
sudo -u minecraft -H sh -c 'cd /opt/minecraft/server && java -Xms4G -Xmx4G -XX:+UseG1GC -jar paper.jar --nogui'
```

- Read the console output. If it reports an unsupported Java version or another startup error, resolve that before continuing.
- Review `eula.txt` and set `eula=true` only if you agree to Mojang's EULA. Then run the same start command again and wait for Paper's ready message. Stop the test server cleanly before proceeding.

Do not download a JAR from an unofficial mirror or rename an unverified file and treat it as trusted.

### 7. Set basic server properties

Stop Paper cleanly before editing `server.properties`. Set or verify these values, keeping the existing file's formatting:

```properties
server-port=25565
server-ip=
online-mode=true
enable-rcon=false
view-distance=6
simulation-distance=4
white-list=true
```

Keep `server-ip` empty unless you have a specific reason to bind the server to one local interface. Keeping the whitelist on during setup gives you time to test before admitting the public. Add players after confirming the names Paper sees for both Java and Floodgate-authenticated Bedrock accounts.

Start the server and verify that it reaches the ready state. From the server console, apply the gameplay rule if desired:

```text
gamerule keepInventory true
```

### 8. Add a managed startup service

After the basic server starts successfully, create `/etc/systemd/system/minecraft.service`:

```ini
[Unit]
Description=Minecraft Paper Server
After=network.target

[Service]
User=minecraft
Group=minecraft
WorkingDirectory=/opt/minecraft/server
ExecStart=/usr/bin/java -Xms4G -Xmx4G -XX:+UseG1GC -jar paper.jar --nogui
Restart=on-failure
RestartSec=10
KillSignal=SIGINT
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
```

The 4 GB heap is intentional for the 12 GB instance. Start with this straightforward G1GC configuration; use only JVM flags appropriate for the selected Java and Paper versions rather than copying an old flag bundle without checking it.

Load and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now minecraft
sudo systemctl status minecraft
sudo journalctl -u minecraft -n 100 --no-pager
```

Confirm the server starts, stops, and starts again cleanly. Use `sudo systemctl stop minecraft` for a normal stop; do not kill the Java process abruptly during ordinary maintenance.

### 9. Install Geyser and Floodgate, then test Bedrock

- Stop the server.
- Download the Paper/Spigot-compatible Geyser and Floodgate JARs from their official sources and place them in `/opt/minecraft/server/plugins/`.
- Set file ownership to `minecraft:minecraft`, start the server, and let the plugins generate their configuration.
- Stop the server and configure Geyser's authentication mode to use Floodgate. Confirm Geyser listens on UDP `19132` and uses the intended public address.
- Start the server and check the log for successful Geyser and Floodgate startup and for UDP bind errors.
- Test a Bedrock login from a supported Bedrock client. Confirm that the player can move, chat, and interact with the world.

Keep Floodgate's generated private key on the server. Never add it to GitHub or share it publicly. Keep Java `online-mode` enabled; Floodgate is the Bedrock authentication bridge.

### 10. Install ViaVersion and ViaBackwards, then test Java versions

- Stop the server and add compatible ViaVersion and ViaBackwards JARs from their official sources.
- Start the server and check the logs for version or dependency errors.
- Test a Java client on the server's native protocol version, then test the specific newer and older client versions you intend to support.

ViaBackwards depends on ViaVersion. These plugins extend Java-client compatibility; they do not extend Bedrock compatibility. Do not promise support for client versions outside the plugins' current documented ranges.

### 11. Install EssentialsX, EssentialsXChat, and Vault

- Install the EssentialsX core and EssentialsXChat modules that match the selected server version.
- Install Vault from its official source for LuckPerms/EssentialsX chat integration.
- Start the server once so configuration files are generated, then stop it before editing.
- Configure only the commands and features you intend to offer. For the planned setup, review home, spawn, teleport request, pay, back, hat, nick, and chat settings.
- Configure the chat format to display the LuckPerms prefix and test it with ordinary player accounts. EssentialsXChat configuration keys can differ between releases, so edit the generated configuration for the installed version rather than replacing the entire file with a snippet from another release.

Vault is included here for the planned prefix/chat integration. It is a bridge, not a standalone economy or permission manager.

### 12. Install LuckPerms and configure the ranks

Install the LuckPerms Paper plugin, start the server, and configure it through the console or the in-game command interface as an operator. The following is the intended permission design; confirm each EssentialsX permission against the documentation for the installed version.

LuckPerms normally creates a `default` group during installation. Check that it exists rather than trying to create it again. Create the supporter group and inheritance:

```text
lp creategroup supporter
lp group supporter parent add default
```

Give the default group the planned basic permissions:

```text
lp group default permission set essentials.sethome true
lp group default permission set essentials.home true
lp group default permission set essentials.delhome true
lp group default permission set essentials.sethome.multiple true
lp group default permission set essentials.sethome.multiple.default true
lp group default permission set essentials.spawn true
lp group default permission set essentials.tpa true
lp group default permission set essentials.tpaccept true
lp group default permission set essentials.pay true
```

Give supporters the higher home limit and the additional features:

```text
lp group supporter permission set essentials.sethome.multiple.supporter true
lp group supporter permission set essentials.back true
lp group supporter permission set essentials.hat true
lp group supporter permission set essentials.nick true
lp group supporter permission set essentials.chat.color true
```

Set the group prefixes:

```text
lp group default meta setprefix 100 "&7[Member] "
lp group supporter meta setprefix 200 "&a&l[Supporter] "
```

Use the LuckPerms web editor only if you understand that its link contains an editable permission snapshot. Do not share a link containing changes you do not intend to publish.

### 13. Configure EssentialsX home limits and test permissions

In the generated EssentialsX configuration, find the `sethome-multiple` section. Configure the two named limits according to that file's format; the intended limits are:

```yaml
sethome-multiple:
  default: 1
  supporter: 3
```

Use the corresponding EssentialsX permission nodes assigned in Step 12. Restart the server after editing and test with:

- A default player: can set and use one home, but cannot create a second.
- A supporter: can set and use up to three homes, but cannot create a fourth.
- A default player: cannot use supporter-only commands such as `/back` or `/hat`.
- A supporter: receives the supporter prefix and the intended chat color permission.

Do not use an operator account for these tests; operator status can bypass the permission behavior you are trying to verify.

### 14. Install and configure GriefPrevention

- Install the compatible GriefPrevention plugin, start the server to generate its files, and inspect its generated configuration.
- Decide the claim-block earning rate, maximum claim size, behavior near spawn, and whether players may trust others in claims.
- Keep the initial policy simple: players can protect their own builds, and trust is granted deliberately by the claim owner.
- Test with two non-operator accounts: one claims land and builds; the other attempts to modify it and should be blocked. Also test the intended trust behavior.

Change one claim setting at a time and retest, especially settings that affect spawn protection or claim limits.

### 15. Pre-generate the world with Chunky (optional)

Chunky is optional. First decide the intended playable world area and confirm adequate disk space. Then install the compatible Chunky plugin, start the server, and use its documented commands to select the world, center, radius, and start the generation. Monitor CPU, memory, disk space, and server responsiveness while it runs.

Do not generate an arbitrarily large area on a 2-OCPU instance. Pause or stop generation if the server becomes unresponsive or storage is running low.

### 16. Test the complete server before opening it to players

Use a checklist and record the results:

- Paper starts without errors and the service survives a reboot.
- Java connects over TCP 25565.
- Bedrock connects over UDP 19132 through Geyser/Floodgate.
- The tested Java and Bedrock client versions are within the plugins' supported ranges.
- The whitelist behaves as intended for Java and Floodgate player names.
- Default and supporter home limits, commands, prefixes, and chat permissions work.
- Claims prevent unauthorized building and allow the intended trust behavior.
- `keepInventory` has the intended value, if enabled.
- Stopping the service saves the world and restarting it does not report world or plugin errors.

Only after these tests pass should you disable the whitelist, if you want the server to be public.

### 17. Set up backups and a maintenance routine

Before inviting players, decide where backups will be stored, how often they will run, and how many copies to retain. Back up the world and the configurations needed to rebuild the server. Keep backups off the same instance when practical, and restrict access to them.

For a manual consistent backup, stop the service, create a dated archive outside the live server directory, and start the service again:

```bash
sudo systemctl stop minecraft
sudo tar -czf /opt/minecraft/backups/server-$(date +%F-%H%M).tar.gz -C /opt/minecraft/server .
sudo chown minecraft:minecraft /opt/minecraft/backups/server-*.tar.gz
sudo systemctl start minecraft
```

Review the archive and test a restore to a separate directory before relying on it. Automate this only after the manual process is confirmed, and add retention so old backups do not fill the disk.

For updates: stop the server, take and verify a backup, check Paper and plugin compatibility notes, update a controlled set of files, then start the server and inspect logs before reopening it.

## GitHub publishing checklist

This folder is for the guide and safe templates, not the live server. Before publishing:

- Review every file for passwords, tokens, private keys, public IPs you do not want to share, or other private information.
- Do not add the live world, runtime directory, plugin JARs, generated `server.properties`, logs, or Floodgate private key.
- Use a private repository if the guide will contain private operational details.
- Create a GitHub repository, then from this project folder initialize Git and push the documentation. Replace the placeholders with your own repository URL:

```bash
git init
git add README.md .gitignore
git commit -m "Add Minecraft server setup guide"
git branch -M main
git remote add origin https://github.com/<your-account>/<your-repository>.git
git push -u origin main
```

If this folder is later connected to an existing Git repository, inspect `git status` and the configured remote before committing or pushing.
