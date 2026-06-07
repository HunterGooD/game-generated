use criterion::{criterion_group, criterion_main, Criterion};
use echoes_server::protocol::ClientMessage;
use echoes_server::router::route_message;

fn bench_route_broadcast(c: &mut Criterion) {
    let msg = serde_json::json!({"t":"pos","x":10.0,"y":20.0,"fr":true,"a":"walk"});
    let recipients: Vec<u8> = (0..4).collect();

    c.bench_function("route_broadcast_4p", |b| {
        b.iter(|| {
            let _ = route_message(
                0,
                0,
                &recipients,
                &ClientMessage::Pos {
                    x: 10.0,
                    y: 20.0,
                    fr: true,
                    a: "walk".to_string(),
                },
                &msg,
            );
        })
    });
}

criterion_group!(benches, bench_route_broadcast);
criterion_main!(benches);
