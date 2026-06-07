use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRoomRequest {
    pub max_players: u8,
}

impl CreateRoomRequest {
    pub fn validate(&self) -> Result<(), String> {
        if (2..=4).contains(&self.max_players) {
            Ok(())
        } else {
            Err("max_players must be between 2 and 4".to_string())
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateRoomResponse {
    pub code: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub error: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub rooms: usize,
    pub players: usize,
}

pub fn joined_message(player_id: u8, total: usize, max_players: u8) -> Value {
    serde_json::json!({
        "t": "joined",
        "player_id": player_id,
        "total": total,
        "max_players": max_players,
    })
}

pub fn player_disconnected_message(player_id: u8) -> Value {
    serde_json::json!({
        "t": "player_disconnected",
        "player_id": player_id,
    })
}

pub fn pong_message() -> Value {
    serde_json::json!({ "t": "pong" })
}

pub fn with_from(mut msg: Value, from: u8) -> Value {
    if let Value::Object(ref mut obj) = msg {
        obj.insert("from".to_string(), Value::from(from));
        return msg;
    }
    let mut obj = Map::new();
    obj.insert("t".to_string(), Value::String("invalid".to_string()));
    obj.insert("from".to_string(), Value::from(from));
    Value::Object(obj)
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "t")]
pub enum ClientMessage {
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "lobby_class")]
    LobbyClass { class_id: String },
    #[serde(rename = "lobby_ready")]
    LobbyReady { ready: bool },
    #[serde(rename = "lobby_start")]
    LobbyStart,
    #[serde(rename = "room_config")]
    RoomConfig { max_players: u8 },
    #[serde(rename = "pos")]
    Pos {
        x: f64,
        y: f64,
        fr: bool,
        a: String,
    },
    #[serde(rename = "skill_cast")]
    SkillCast {
        sid: String,
        path: String,
        x: f64,
        y: f64,
        dx: f64,
        dy: f64,
        d: i64,
    },
    #[serde(rename = "enemy_spawn")]
    EnemySpawn {
        id: i64,
        #[serde(rename = "type")]
        enemy_type: String,
        x: f64,
        y: f64,
        hp: i64,
        dmg: i64,
        ranged: bool,
        scale: f64,
    },
    #[serde(rename = "enemy_state")]
    EnemyState { enemies: Vec<Value> },
    #[serde(rename = "enemy_death")]
    EnemyDeath {
        id: i64,
        x: f64,
        y: f64,
        gold_min: i64,
        gold_max: i64,
        xp: i64,
    },
    #[serde(rename = "enemy_hit")]
    EnemyHit { id: i64, damage: i64 },
    #[serde(rename = "boss_spawn")]
    BossSpawn {
        id: i64,
        boss_id: String,
        wave: i64,
        x: f64,
        y: f64,
    },
    #[serde(rename = "boss_state")]
    BossState {
        id: i64,
        hp: i64,
        max_hp: i64,
        x: f64,
        y: f64,
    },
    #[serde(rename = "wave_started")]
    WaveStarted { wave: i64 },
    #[serde(rename = "wave_cleared")]
    WaveCleared { wave: i64 },
    #[serde(rename = "merchant_spawn")]
    MerchantSpawn { x: f64, y: f64 },
    #[serde(rename = "portal_spawn")]
    PortalSpawn { x: f64, y: f64 },
    #[serde(rename = "portal_consumed")]
    PortalConsumed,
    #[serde(rename = "portal_activate")]
    PortalActivate,
    #[serde(rename = "chest_spawn")]
    ChestSpawn {
        owner: u8,
        wave: i64,
        x: f64,
        y: f64,
        forced_rarity: Option<String>,
    },
    #[serde(rename = "rp_hp")]
    RpHp { target: u8, hp: i64 },
    #[serde(rename = "druid_form")]
    DruidForm { form: String, dur: f64 },
    #[serde(rename = "player_dead")]
    PlayerDead,
    #[serde(rename = "player_downed")]
    PlayerDowned,
    #[serde(rename = "player_revived")]
    PlayerRevived { hp: i64 },
    #[serde(rename = "revive")]
    Revive { target: u8 },
    #[serde(rename = "pause_request")]
    PauseRequest { paused: bool },
    #[serde(rename = "item_gift")]
    ItemGift { to: u8, item: Value },
    // Host-authoritative summons (pets / skeletons). A client asks the host to
    // spawn its summon; the host owns the unit's AI/combat and replicates it.
    #[serde(rename = "summon_request")]
    SummonRequest {
        kind: String,
        pet: String,
        x: f64,
        y: f64,
        count: i64,
        dmg: i64,
        armor: i64,
    },
    #[serde(rename = "minion_spawn")]
    MinionSpawn {
        id: i64,
        kind: String,
        pet: String,
        x: f64,
        y: f64,
        owner: u8,
        dmg: i64,
        armor: i64,
    },
    #[serde(rename = "minion_state")]
    MinionState { minions: Vec<Value> },
    #[serde(rename = "minion_death")]
    MinionDeath { id: i64 },
    // Client → host: empower the requesting player's host-side minions.
    #[serde(rename = "blood_pact")]
    BloodPact {
        duration: f64,
        dmg_mult: f64,
        speed_mult: f64,
    },
}

impl ClientMessage {
    pub fn message_type(&self) -> &'static str {
        match self {
            Self::Ping => "ping",
            Self::LobbyClass { .. } => "lobby_class",
            Self::LobbyReady { .. } => "lobby_ready",
            Self::LobbyStart => "lobby_start",
            Self::RoomConfig { .. } => "room_config",
            Self::Pos { .. } => "pos",
            Self::SkillCast { .. } => "skill_cast",
            Self::EnemySpawn { .. } => "enemy_spawn",
            Self::EnemyState { .. } => "enemy_state",
            Self::EnemyDeath { .. } => "enemy_death",
            Self::EnemyHit { .. } => "enemy_hit",
            Self::BossSpawn { .. } => "boss_spawn",
            Self::BossState { .. } => "boss_state",
            Self::WaveStarted { .. } => "wave_started",
            Self::WaveCleared { .. } => "wave_cleared",
            Self::MerchantSpawn { .. } => "merchant_spawn",
            Self::PortalSpawn { .. } => "portal_spawn",
            Self::PortalConsumed => "portal_consumed",
            Self::PortalActivate => "portal_activate",
            Self::ChestSpawn { .. } => "chest_spawn",
            Self::RpHp { .. } => "rp_hp",
            Self::DruidForm { .. } => "druid_form",
            Self::PlayerDead => "player_dead",
            Self::PlayerDowned => "player_downed",
            Self::PlayerRevived { .. } => "player_revived",
            Self::Revive { .. } => "revive",
            Self::PauseRequest { .. } => "pause_request",
            Self::ItemGift { .. } => "item_gift",
            Self::SummonRequest { .. } => "summon_request",
            Self::MinionSpawn { .. } => "minion_spawn",
            Self::MinionState { .. } => "minion_state",
            Self::MinionDeath { .. } => "minion_death",
            Self::BloodPact { .. } => "blood_pact",
        }
    }

    pub fn validate(&self) -> Result<(), String> {
        match self {
            Self::RoomConfig { max_players } if !(2..=4).contains(max_players) => {
                Err("room_config.max_players must be between 2 and 4".to_string())
            }
            Self::ItemGift { item, .. } if !item.is_object() => {
                Err("item_gift.item must be object".to_string())
            }
            _ => Ok(()),
        }
    }
}

pub fn parse_client_message(raw: &str) -> Result<(ClientMessage, Value), String> {
    let value: Value = serde_json::from_str(raw).map_err(|e| format!("invalid json: {e}"))?;
    let msg: ClientMessage =
        serde_json::from_value(value.clone()).map_err(|e| format!("invalid message schema: {e}"))?;
    msg.validate()?;
    Ok((msg, value))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_room_request_validation() {
        assert!(CreateRoomRequest { max_players: 2 }.validate().is_ok());
        assert!(CreateRoomRequest { max_players: 4 }.validate().is_ok());
        assert!(CreateRoomRequest { max_players: 1 }.validate().is_err());
    }

    #[test]
    fn parses_and_validates_all_supported_messages() {
        let samples = [
            r#"{"t":"ping"}"#,
            r#"{"t":"lobby_class","class_id":"mage"}"#,
            r#"{"t":"lobby_ready","ready":true}"#,
            r#"{"t":"lobby_start"}"#,
            r#"{"t":"room_config","max_players":3}"#,
            r#"{"t":"pos","x":1.0,"y":2.0,"fr":true,"a":"idle"}"#,
            r#"{"t":"skill_cast","sid":"fire_wall","path":"res://x.tscn","x":1.0,"y":2.0,"dx":1.0,"dy":0.0,"d":10}"#,
            r#"{"t":"enemy_spawn","id":1,"type":"skeleton","x":0.0,"y":0.0,"hp":10,"dmg":2,"ranged":false,"scale":0.34}"#,
            r#"{"t":"enemy_state","enemies":[]}"#,
            r#"{"t":"enemy_death","id":1,"x":0.0,"y":0.0,"gold_min":1,"gold_max":2,"xp":3}"#,
            r#"{"t":"enemy_hit","id":1,"damage":2}"#,
            r#"{"t":"boss_spawn","id":1,"boss_id":"lich","wave":5,"x":0.0,"y":0.0}"#,
            r#"{"t":"boss_state","id":1,"hp":10,"max_hp":20,"x":0.0,"y":0.0}"#,
            r#"{"t":"wave_started","wave":2}"#,
            r#"{"t":"wave_cleared","wave":2}"#,
            r#"{"t":"merchant_spawn","x":1.0,"y":2.0}"#,
            r#"{"t":"portal_spawn","x":1.0,"y":2.0}"#,
            r#"{"t":"portal_consumed"}"#,
            r#"{"t":"portal_activate"}"#,
            r#"{"t":"chest_spawn","owner":0,"wave":2,"x":1.0,"y":2.0,"forced_rarity":"legendary"}"#,
            r#"{"t":"rp_hp","target":1,"hp":80}"#,
            r#"{"t":"druid_form","form":"wolf","dur":20.0}"#,
            r#"{"t":"player_dead"}"#,
            r#"{"t":"player_downed"}"#,
            r#"{"t":"player_revived","hp":80}"#,
            r#"{"t":"revive","target":1}"#,
            r#"{"t":"pause_request","paused":true}"#,
            r#"{"t":"item_gift","to":1,"item":{"id":"x"}}"#,
            r#"{"t":"summon_request","kind":"spirit","pet":"wolf","x":1.0,"y":2.0,"count":1,"dmg":14,"armor":0}"#,
            r#"{"t":"minion_spawn","id":1,"kind":"skeleton","pet":"","x":1.0,"y":2.0,"owner":1,"dmg":7,"armor":0}"#,
            r#"{"t":"minion_state","minions":[]}"#,
            r#"{"t":"minion_death","id":1}"#,
            r#"{"t":"blood_pact","duration":10.0,"dmg_mult":1.75,"speed_mult":1.3}"#,
        ];
        for sample in samples {
            let parsed = parse_client_message(sample);
            assert!(parsed.is_ok(), "failed to parse sample: {sample}");
        }
    }

    #[test]
    fn rejects_invalid_message_schema() {
        assert!(parse_client_message(r#"{"t":"room_config","max_players":8}"#).is_err());
        assert!(parse_client_message(r#"{"t":"item_gift","to":1,"item":5}"#).is_err());
        assert!(parse_client_message(r#"{"t":"unknown"}"#).is_err());
    }
}
