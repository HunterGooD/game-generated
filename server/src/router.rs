use serde_json::Value;

use crate::protocol::{pong_message, with_from, ClientMessage};

#[derive(Debug, Clone, PartialEq)]
pub struct RoutedMessage {
    pub target: u8,
    pub payload: Value,
}

pub fn route_message(
    from: u8,
    host_id: u8,
    recipients: &[u8],
    typed: &ClientMessage,
    msg: &Value,
) -> Vec<RoutedMessage> {
    match typed {
        ClientMessage::Ping => vec![RoutedMessage {
            target: from,
            payload: pong_message(),
        }],
        ClientMessage::ItemGift { to, .. } => {
            let t = *to;
            if recipients.contains(&t) && t != from {
                vec![RoutedMessage {
                    target: t,
                    payload: with_from(msg.clone(), from),
                }]
            } else {
                Vec::new()
            }
        }
        // Revive is addressed to the downed player who owns their own life
        // state; deliver only to that target (they then broadcast revived).
        ClientMessage::Revive { target } => {
            let t = *target;
            if recipients.contains(&t) && t != from {
                vec![RoutedMessage {
                    target: t,
                    payload: with_from(msg.clone(), from),
                }]
            } else {
                Vec::new()
            }
        }
        ClientMessage::EnemyHit { .. }
        | ClientMessage::PortalActivate
        | ClientMessage::SummonRequest { .. }
        | ClientMessage::BloodPact { .. } => {
            if host_id == from {
                Vec::new()
            } else {
                vec![RoutedMessage {
                    target: host_id,
                    payload: with_from(msg.clone(), from),
                }]
            }
        }
        _ => {
            let relayed = with_from(msg.clone(), from);
            recipients
                .iter()
                .copied()
                .filter(|pid| *pid != from)
                .map(|target| RoutedMessage {
                    target,
                    payload: relayed.clone(),
                })
                .collect()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ping_returns_pong_to_sender() {
        let msg = serde_json::json!({"t":"ping"});
        let out = route_message(2, 0, &[0, 1, 2], &ClientMessage::Ping, &msg);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].target, 2);
        assert_eq!(out[0].payload["t"], "pong");
    }

    #[test]
    fn item_gift_is_directed() {
        let msg = serde_json::json!({"t":"item_gift", "to": 1, "item": {"id": "x"}});
        let out = route_message(
            0,
            0,
            &[0, 1, 2],
            &ClientMessage::ItemGift {
                to: 1,
                item: serde_json::json!({"id":"x"}),
            },
            &msg,
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].target, 1);
        assert_eq!(out[0].payload["from"], 0);
    }

    #[test]
    fn enemy_hit_goes_to_host_only() {
        let msg = serde_json::json!({"t":"enemy_hit", "id": 7, "damage": 3});
        let out = route_message(
            2,
            0,
            &[0, 1, 2],
            &ClientMessage::EnemyHit { id: 7, damage: 3 },
            &msg,
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].target, 0);
    }

    #[test]
    fn broadcast_excludes_sender() {
        let msg = serde_json::json!({"t":"lobby_ready", "ready": true});
        let out = route_message(
            1,
            0,
            &[0, 1, 2],
            &ClientMessage::LobbyReady { ready: true },
            &msg,
        );
        assert_eq!(out.len(), 2);
        assert!(out.iter().all(|m| m.target != 1));
    }
}
