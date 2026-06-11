use std::collections::HashMap;
use std::time::Instant;

use axum::extract::ws::Message;
use rand::Rng;
use tokio::sync::mpsc;

use crate::router;
use crate::protocol::ClientMessage;

pub type PeerTx = mpsc::UnboundedSender<Message>;

#[derive(Debug)]
pub struct Room {
    pub code: String,
    pub max_players: u8,
    pub host_id: u8,
    // App/protocol version the host created the room with. Joiners must match.
    pub version: String,
    peers: HashMap<u8, PeerTx>,
    pub empty_since: Option<Instant>,
}

impl Room {
    pub fn new(code: String, max_players: u8, version: String) -> Self {
        Self {
            code,
            max_players,
            host_id: 0,
            version,
            peers: HashMap::new(),
            empty_since: Some(Instant::now()),
        }
    }

    pub fn allocate_player_id(&self) -> Option<u8> {
        (0..self.max_players).find(|id| !self.peers.contains_key(id))
    }

    pub fn add_peer(&mut self, player_id: u8, tx: PeerTx) {
        self.peers.insert(player_id, tx);
        self.empty_since = None;
    }

    pub fn remove_peer(&mut self, player_id: u8) {
        self.peers.remove(&player_id);
        if self.peers.is_empty() {
            self.empty_since = Some(Instant::now());
        }
    }

    pub fn peer_count(&self) -> usize {
        self.peers.len()
    }

    pub fn is_full(&self) -> bool {
        self.peers.len() >= self.max_players as usize
    }

    pub fn is_empty(&self) -> bool {
        self.peers.is_empty()
    }

    pub fn peer_ids(&self) -> Vec<u8> {
        self.peers.keys().copied().collect()
    }

    pub fn send_json(&self, target: u8, value: &serde_json::Value) {
        if let Some(tx) = self.peers.get(&target) {
            let _ = tx.send(Message::Text(value.to_string()));
        }
    }

    pub fn route_and_send(&self, from: u8, typed: &ClientMessage, msg: &serde_json::Value) {
        let recipients = self.peer_ids();
        let routed = router::route_message(from, self.host_id, &recipients, typed, msg);
        for item in routed {
            self.send_json(item.target, &item.payload);
        }
    }
}

pub fn generate_room_code(len: usize) -> String {
    // Digits-only codes ("Лобби 123456") — easy to read aloud and type. 10^len
    // combinations; create_room retries on the rare collision.
    let mut rng = rand::thread_rng();
    std::iter::repeat_with(|| rng.gen_range(b'0'..=b'9'))
        .map(char::from)
        .take(len)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn code_length_and_charset() {
        let code = generate_room_code(6);
        assert_eq!(code.len(), 6);
        assert!(code.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn allocate_reuses_gaps() {
        let mut room = Room::new("ABC123".to_string(), 4, String::new());
        let (tx0, _rx0) = mpsc::unbounded_channel();
        let (tx1, _rx1) = mpsc::unbounded_channel();
        room.add_peer(0, tx0);
        room.add_peer(1, tx1);
        room.remove_peer(0);
        assert_eq!(room.allocate_player_id(), Some(0));
    }
}
