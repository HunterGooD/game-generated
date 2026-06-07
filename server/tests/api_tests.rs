use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use echoes_server::api::{app_router, AppState, Config};
use tower::ServiceExt;

#[tokio::test]
async fn create_room_returns_code() {
    let app = app_router(AppState::new(Config::default()));
    let req = Request::builder()
        .method("POST")
        .uri("/lobby/create")
        .header("content-type", "application/json")
        .body(Body::from(r#"{"max_players":3}"#))
        .unwrap();

    let res = app.oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
}

#[tokio::test]
async fn health_endpoint_works() {
    let app = app_router(AppState::new(Config::default()));
    let req = Request::builder()
        .method("GET")
        .uri("/health")
        .body(Body::empty())
        .unwrap();

    let res = app.oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
}

#[tokio::test]
async fn create_room_rejects_invalid_max_players() {
    let app = app_router(AppState::new(Config::default()));
    let req = Request::builder()
        .method("POST")
        .uri("/lobby/create")
        .header("content-type", "application/json")
        .body(Body::from(r#"{"max_players":9}"#))
        .unwrap();

    let res = app.oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn metrics_endpoint_works() {
    let app = app_router(AppState::new(Config::default()));
    let req = Request::builder()
        .method("GET")
        .uri("/metrics")
        .body(Body::empty())
        .unwrap();

    let res = app.oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
}
