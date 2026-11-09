/*
 * Local Trainer: source-written local bot practice plugin for AMX Mod X.
 * This is not derived from the packed Application.dll.
 * No networking, downloading, shell execution, or DLL injection natives.
 */
#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <hlsdk_const>

#define PLUGIN_VERSION "0.1.0"
#define MAX_CLIENTS 32
#define RADAR_RANGE 1600.0
#define TRAINER_SPEED 480.0

new bool:g_enabled[MAX_CLIENTS + 1];
new bool:g_aim[MAX_CLIENTS + 1];
new bool:g_radar[MAX_CLIENTS + 1];
new bool:g_speed[MAX_CLIENTS + 1];
new Float:g_original_speed[MAX_CLIENTS + 1];
new bool:g_speed_applied[MAX_CLIENTS + 1];
new Float:g_server_maxspeed;
new bool:g_changed_server_maxspeed;
new g_maxplayers;
new g_snapshot_file[256];
new bool:g_snapshot_live;

public plugin_init()
{
    register_plugin("Local Bot Trainer", PLUGIN_VERSION, "Local Trainer");
    register_clcmd("say /trainer", "open_trainer");
    register_clcmd("trainer_menu", "open_trainer");
    register_clcmd("trainer_toggle", "command_toggle");
    register_clcmd("trainer_aim", "command_aim");
    register_clcmd("trainer_radar", "command_radar");
    register_clcmd("trainer_speed", "command_speed");
    register_forward(FM_CmdStart, "on_cmd_start");
    register_forward(FM_PlayerPreThink, "on_prethink");
    set_task(0.3, "update_radar", 1185, "", 0, "b");
    set_task(0.1, "update_snapshot", 1186, "", 0, "b");
    g_maxplayers = get_maxplayers();
    new data_dir[192];
    get_datadir(data_dir, charsmax(data_dir));
    formatex(g_snapshot_file, charsmax(g_snapshot_file), "%s/lt_local_snapshot.txt", data_dir);
    delete_file(g_snapshot_file);
}

public plugin_end()
{
    clear_snapshot();
    restore_server_maxspeed();
}

public client_disconnected(id)
{
    if (g_speed[id]) stop_speed(id);
    g_enabled[id] = false;
    g_aim[id] = false;
    g_radar[id] = false;
    g_speed[id] = false;
}

// Only the local listen-server player is allowed, and only with bot opponents.
// A second human causes every feature to stop until the human leaves.
bool:allowed(id)
{
    if (id < 1 || id > g_maxplayers || !is_user_connected(id) || is_user_bot(id) || is_user_hltv(id)) return false;
    new humans;
    for (new i = 1; i <= g_maxplayers; i++) {
        if (is_user_connected(i) && !is_user_bot(i) && !is_user_hltv(i)) humans++;
    }
    if (humans != 1) return false;
    new ip[48];
    get_user_ip(id, ip, charsmax(ip), 1);
    return bool:(equal(ip, "127.0.0.1") || equal(ip, "loopback") || equal(ip, "localhost") || equal(ip, "::1"));
}

public open_trainer(id)
{
    if (!allowed(id)) {
        client_print(id, print_chat, "[Trainer] Local listen-server with one human only.");
        return PLUGIN_HANDLED;
    }
    new menu = menu_create("Local Bot Trainer", "handle_menu");
    new item[96];
    formatex(item, charsmax(item), "Program: %s", g_enabled[id] ? "ON" : "OFF");
    menu_additem(menu, item, "0");
    formatex(item, charsmax(item), "Head aim + fire: %s", g_aim[id] ? "ON" : "OFF");
    menu_additem(menu, item, "1");
    formatex(item, charsmax(item), "Radar and markers: %s", g_radar[id] ? "ON" : "OFF");
    menu_additem(menu, item, "2");
    formatex(item, charsmax(item), "High speed: %s", g_speed[id] ? "ON" : "OFF");
    menu_additem(menu, item, "3");
    menu_display(id, menu);
    return PLUGIN_HANDLED;
}

public handle_menu(id, menu, item)
{
    if (item == MENU_EXIT || !allowed(id)) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }
    new data[4], label[2], access, callback;
    menu_item_getinfo(menu, item, access, data, charsmax(data), label, charsmax(label), callback);
    toggle_feature(id, str_to_num(data));
    menu_destroy(menu);
    open_trainer(id);
    return PLUGIN_HANDLED;
}


public command_toggle(id) { return hotkey(id, 0); }
public command_aim(id) { return hotkey(id, 1); }
public command_radar(id) { return hotkey(id, 2); }
public command_speed(id) { return hotkey(id, 3); }

hotkey(id, feature)
{
    if (!allowed(id)) {
        if (id > 0 && id <= g_maxplayers && is_user_connected(id))
            client_print(id, print_chat, "[Trainer] Local listen-server with one human only.");
        return PLUGIN_HANDLED;
    }
    toggle_feature(id, feature);
    return PLUGIN_HANDLED;
}

toggle_feature(id, feature)
{
    switch (feature) {
        case 0: {
            g_enabled[id] = !g_enabled[id];
            if (!g_enabled[id] && g_speed[id]) stop_speed(id);
            if (g_enabled[id] && g_speed[id]) start_speed(id);
            client_print(id, print_chat, "[Trainer] Program: %s", g_enabled[id] ? "ON" : "OFF");
        }
        case 1: {
            g_aim[id] = !g_aim[id];
            client_print(id, print_chat, "[Trainer] Head aim and fire: %s%s", g_aim[id] ? "ON" : "OFF", !g_enabled[id] ? " (program OFF)" : "");
        }
        case 2: {
            g_radar[id] = !g_radar[id];
            client_print(id, print_chat, "[Trainer] Radar and markers: %s%s", g_radar[id] ? "ON" : "OFF", !g_enabled[id] ? " (program OFF)" : "");
        }
        case 3: {
            g_speed[id] = !g_speed[id];
            if (g_speed[id] && g_enabled[id]) start_speed(id);
            else stop_speed(id);
            client_print(id, print_chat, "[Trainer] Speed: %s%s", g_speed[id] ? "ON" : "OFF", !g_enabled[id] ? " (program OFF)" : "");
        }
    }
}

start_speed(id)
{
    if (g_speed_applied[id] || !is_user_alive(id)) return;
    pev(id, pev_maxspeed, g_original_speed[id]);
    g_speed_applied[id] = true;
    if (!g_changed_server_maxspeed) {
        g_server_maxspeed = get_cvar_float("sv_maxspeed");
        if (g_server_maxspeed < TRAINER_SPEED) {
            set_cvar_float("sv_maxspeed", TRAINER_SPEED);
            g_changed_server_maxspeed = true;
        }
    }
}

restore_server_maxspeed()
{
    // Avoid overwriting a value changed independently by the server operator.
    if (g_changed_server_maxspeed && get_cvar_float("sv_maxspeed") == TRAINER_SPEED)
        set_cvar_float("sv_maxspeed", g_server_maxspeed);
    g_changed_server_maxspeed = false;
}

stop_speed(id)
{
    if (is_user_connected(id) && is_user_alive(id) && g_original_speed[id] > 1.0)
        set_pev(id, pev_maxspeed, g_original_speed[id]);
    g_original_speed[id] = 0.0;
    g_speed_applied[id] = false;
    restore_server_maxspeed();
}

public on_prethink(id)
{
    if (id < 1 || id > g_maxplayers || !is_user_connected(id)) return FMRES_IGNORED;
    if (!allowed(id)) {
        if (g_speed_applied[id]) stop_speed(id);
        return FMRES_IGNORED;
    }
    if (g_enabled[id] && g_speed[id] && is_user_alive(id)) {
        if (!g_speed_applied[id]) start_speed(id);
        set_pev(id, pev_maxspeed, TRAINER_SPEED);
    }
    return FMRES_IGNORED;
}

public on_cmd_start(id, uc, seed)
{
    if (!allowed(id) || !is_user_alive(id) || !g_enabled[id] || !g_aim[id]) return FMRES_IGNORED;
    new team = get_user_team(id);
    if (team != 1 && team != 2) return FMRES_IGNORED;
    new Float:origin[3], Float:viewofs[3], Float:eye[3];
    pev(id, pev_origin, origin);
    pev(id, pev_view_ofs, viewofs);
    for (new n = 0; n < 3; n++) eye[n] = origin[n] + viewofs[n];
    new target, Float:best = 999999999.0, Float:target_eye[3];
    new trace = create_tr2();
    for (new i = 1; i <= g_maxplayers; i++) {
        if (!is_user_alive(i) || !is_user_bot(i) || get_user_team(i) == team) continue;
        new Float:pos[3], Float:offset[3];
        pev(i, pev_origin, pos);
        pev(i, pev_view_ofs, offset);
        for (new n = 0; n < 3; n++) pos[n] += offset[n];
        engfunc(EngFunc_TraceLine, eye, pos, 0, id, trace);
        new Float:fraction;
        get_tr2(trace, TR_flFraction, fraction);
        if (get_tr2(trace, TR_pHit) != i && fraction < 0.99) continue;
        new Float:distance = vector_distance(eye, pos);
        if (distance < best) {
            best = distance;
            target = i;
            for (new n = 0; n < 3; n++) target_eye[n] = pos[n];
        }
    }
    free_tr2(trace);
    if (!target) return FMRES_IGNORED;
    new Float:direction[3], Float:angles[3];
    for (new n = 0; n < 3; n++) direction[n] = target_eye[n] - eye[n];
    engfunc(EngFunc_VecToAngles, direction, angles);
    // GoldSrc pitch uses the opposite sign from vector-to-angles.
    angles[0] = -angles[0];
    set_uc(uc, UC_ViewAngles, angles);
    set_uc(uc, UC_Buttons, get_uc(uc, UC_Buttons) | IN_ATTACK);
    set_pev(id, pev_v_angle, angles);
    set_pev(id, pev_fixangle, 1);
    return FMRES_IGNORED;
}

public update_radar()
{
    for (new id = 1; id <= g_maxplayers; id++) {
        if (!allowed(id) || !is_user_alive(id) || !g_enabled[id] || !g_radar[id]) continue;
        new grid[9][10];
        for (new y = 0; y < 9; y++) {
            for (new x = 0; x < 9; x++) grid[y][x] = '.';
            grid[y][9] = 0;
        }
        new Float:me[3];
        pev(id, pev_origin, me);
        new team = get_user_team(id);
        for (new i = 1; i <= g_maxplayers; i++) {
            if (i == id || !is_user_alive(i) || !is_user_bot(i)) continue;
            new Float:pos[3];
            pev(i, pev_origin, pos);
            new Float:dx = pos[0] - me[0], Float:dy = pos[1] - me[1];
            if (floatabs(dx) > RADAR_RANGE || floatabs(dy) > RADAR_RANGE) continue;
            new gx = clamp(4 + floatround(dx * 4.0 / RADAR_RANGE), 0, 8);
            new gy = clamp(4 - floatround(dy * 4.0 / RADAR_RANGE), 0, 8);
            grid[gy][gx] = get_user_team(i) == team ? 'F' : 'E';
        }
        grid[4][4] = 'P';
        new text[256];
        copy(text, charsmax(text), "P=YOU F=FRIEND E=ENEMY^n");
        for (new y = 0; y < 9; y++) {
            add(text, charsmax(text), grid[y]);
            add(text, charsmax(text), "^n");
        }
        set_hudmessage(100, 230, 100, 0.02, 0.18, 0, 0.0, 0.4, 0.0, 0.0, 4);
        show_hudmessage(id, "%s", text);
    }
}

// Local-only data bridge for the optional windowed-mode overlay. Contains no
// names or network addresses. The overlay ignores incomplete/stale snapshots.
clear_snapshot()
{
    if (g_snapshot_live) delete_file(g_snapshot_file);
    g_snapshot_live = false;
}

public update_snapshot()
{
    new player;
    for (new id = 1; id <= g_maxplayers; id++) {
        if (allowed(id) && is_user_alive(id) && g_enabled[id] && g_radar[id]) {
            player = id;
            break;
        }
    }
    if (!player) {
        clear_snapshot();
        return;
    }
    new file = fopen(g_snapshot_file, "wt");
    if (!file) {
        clear_snapshot();
        return;
    }
    new Float:origin[3], Float:offset[3], Float:angles[3], Float:fov;
    pev(player, pev_origin, origin);
    pev(player, pev_view_ofs, offset);
    pev(player, pev_v_angle, angles);
    pev(player, pev_fov, fov);
    if (fov < 10.0 || fov > 160.0) fov = 90.0;
    new line[192];
    formatex(line, charsmax(line), "LT1^nCAM %.3f %.3f %.3f %.3f %.3f %.3f^n", origin[0]+offset[0], origin[1]+offset[1], origin[2]+offset[2], angles[0], angles[1], fov);
    fputs(file, line);
    new team = get_user_team(player);
    for (new i = 1; i <= g_maxplayers; i++) {
        if (i == player || !is_user_alive(i) || !is_user_bot(i)) continue;
        new bot_team = get_user_team(i);
        if (bot_team != 1 && bot_team != 2) continue;
        new Float:pos[3], Float:mins[3], Float:maxs[3];
        pev(i, pev_origin, pos);
        pev(i, pev_mins, mins);
        pev(i, pev_maxs, maxs);
        formatex(line, charsmax(line), "P %d %.3f %.3f %.3f %.3f %.3f^n", bot_team == team ? 1 : 2, pos[0], pos[1], pos[2], mins[2], maxs[2]);
        fputs(file, line);
    }
    fputs(file, "END^n");
    fclose(file);
    g_snapshot_live = true;
}
