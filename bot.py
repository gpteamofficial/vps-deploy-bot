@bot.tree.command(name="help", description="ℹ️ Show full help with grouped sections and examples")
async def help_command(interaction: discord.Interaction):
    try:
        # اكتشاف الصلاحيات ديناميكياً
        is_admin_flag = await is_admin(interaction)
        # دعم اختياري لـ SUPER_USERS لو مُعرّف كـ set/list/tuple
        try:
            is_super = isinstance(SUPER_USERS, (set, list, tuple)) and interaction.user.id in SUPER_USERS
        except Exception:
            is_super = False

        # أقسام الأوامر
        user_cmds = [
            ("`/list`", "List your instances"),
            ("`/my_usage`", "CPU/RAM & status for your VPSs"),
            ("`/send_ssh <id>`", "DM yourself the SSH (tmate) command"),
            ("`/start <id>`", "Start your instance"),
            ("`/stop <id>`", "Stop your instance"),
            ("`/restart <id>`", "Restart your instance"),
            ("`/regen-ssh <id>`", "Regenerate SSH connection"),
            ("`/remove <id>`", "Delete your instance (permanent)"),
            ("`/rename_vps <id> <alias>`", "Give your VPS an alias"),
            ("`/logs <id> [lines]`", "Show last N log lines"),
            ("`/set_autostop <id> <hours>`", "Auto-stop after idle (0=disable)"),
            ("`/resources`", "Host machine resources"),
            ("`/ping`", "Bot latency"),
            ("`/manage_vps <id>`", "GUI to manage your VPS"),
        ]

        admin_cmds = [
            ("`/deploy user:@u os:<os>`", "[ADMIN] Create instance for a user"),
            ("`/list-all`", "[ADMIN] List all instances with usage"),
            ("`/top_usage [metric] [limit]`", "[ADMIN] Top containers by CPU/RAM"),
            ("`/delete-user-container <id>`", "[ADMIN] Force delete any container"),
            ("`/bulk_stop scope:all`", "[ADMIN] Stop many containers (all)"),
            ("`/vacuum_db`", "[ADMIN] Clean broken DB entries"),
            ("`/transfer_vps <id> @new_owner`", "[ADMIN/Owner] Transfer VPS ownership"),
        ]

        # لو scope:mine يشتغل لليوزر العادي برضه، فنذكره هنا:
        extras_user_friendly = [
            ("`/bulk_stop scope:mine`", "Stop all *your* containers"),
        ]

        super_cmds = [
            ("`/add_admin @member`", "[SUPER] Grant bot-admin role"),
            ("`/remove_admin @member`", "[SUPER] Revoke bot-admin role"),
        ]

        # OS Options (من OS_OPTIONS)
        try:
            os_info = "\n".join([
                f"{data['emoji']} **{key}** — {data['name']}: {data['description']}"
                for key, data in OS_OPTIONS.items()
            ])
        except Exception:
            os_info = "N/A"

        # بناء الـEmbed
        emb = discord.Embed(
            title="✨ Cloud Instance Bot — Help",
            description="All commands grouped by purpose. Use slash-commands in any channel where the bot is allowed.",
            color=EMBED_COLOR
        )

        # أمثلة سريعة
        examples = (
            "**Quick Examples**\n"
            "• Create VPS (admin): ` /deploy user:@Majed os:ubuntu `\n"
            "• Start VPS: ` /start 1a2b3c4d `\n"
            "• Refresh SSH: ` /regen-ssh 1a2b `\n"
            "• Transfer VPS: ` /transfer_vps 1a2b3c4d @NewUser `\n"
            "• Top by RAM (admin): ` /top_usage metric:ram limit:10 `"
        )
        emb.add_field(name="🚀 Examples", value=examples, inline=False)

        # أوامر المستخدمين
        def fmt(lst):
            return "\n".join([f"• {name} — {desc}" for name, desc in lst])

        emb.add_field(name="👤 User Commands", value=fmt(user_cmds), inline=False)

        # bulk_stop (mine) موجه لليوزر
        emb.add_field(name="🧰 Extras", value=fmt(extras_user_friendly), inline=False)

        # أوامر الأدمن (تظهر لمن معاه رول الأدمن فقط)
        if is_admin_flag:
            emb.add_field(name="🛡️ Admin Commands", value=fmt(admin_cmds), inline=False)

        # أوامر الـSUPER (تظهر لو المستخدم ضمن SUPER_USERS)
        if is_super:
            emb.add_field(name="👑 Super Users", value=fmt(super_cmds), inline=False)

        # الـ OS
        emb.add_field(name="🖥️ Available OS", value=os_info or "—", inline=False)

        # معلومات سريعة وسياسات
        tips = (
            "**Notes**\n"
            "• **IDs**: You can pass the first 4+ characters (e.g., `1a2b`).\n"
            "• **Ownership**: Most actions require you to own the VPS (or be admin).\n"
            "• **Auto-stop**: Use `/set_autostop` to save resources.\n"
            "• **Aliases**: Use `/rename_vps` then look for it in `/list` and UI panels.\n"
            "• **Logs**: Use `/logs <id> [lines]` to debug your VPS quickly."
        )
        emb.add_field(name="📎 Tips & Policies", value=tips, inline=False)

        # الفوتر
        try:
            total = len(get_all_servers())
        except Exception:
            total = "?"
        emb.set_footer(text=f"Total instances: {total} • Need help? Contact staff.")

        await interaction.response.send_message(embed=emb, ephemeral=True)

    except Exception as e:
        print("help_command error:", e)
        try:
            await interaction.response.send_message("❌ An error occurred while building help.", ephemeral=True)
        except:
            pass
