;; title: PortFolio
;; version: 1.0.0
;; summary: Decentralized Portfolio Tracker for Stacks-based assets
;; description: An on-chain application that tracks asset holdings and provides verifiable portfolio records

(define-constant contract-owner tx-sender)

(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-unauthorized (err u104))
(define-constant err-invalid-asset (err u105))

(define-data-var total-users uint u0)
(define-data-var platform-fee-rate uint u25)

(define-map user-portfolios 
  { user: principal }
  { 
    created-at: uint,
    last-updated: uint,
    total-value: uint,
    asset-count: uint
  }
)

(define-map user-assets
  { user: principal, asset-id: (string-ascii 64) }
  {
    symbol: (string-ascii 16),
    amount: uint,
    avg-price: uint,
    last-price: uint,
    added-at: uint,
    updated-at: uint
  }
)

(define-map asset-metadata
  { asset-id: (string-ascii 64) }
  {
    symbol: (string-ascii 16),
    name: (string-ascii 32),
    current-price: uint,
    last-updated: uint,
    is-active: bool
  }
)

(define-map user-transactions
  { user: principal, tx-id: uint }
  {
    asset-id: (string-ascii 64),
    action: (string-ascii 8),
    amount: uint,
    price: uint,
    timestamp: uint,
    block-height: uint
  }
)

(define-map user-transaction-counts
  { user: principal }
  { count: uint }
)

(define-map portfolio-permissions
  { owner: principal, viewer: principal }
  { 
    can-view: bool,
    granted-at: uint,
    expires-at: (optional uint)
  }
)

(define-data-var next-tx-id uint u1)

(define-public (initialize-portfolio)
  (let 
    ((user tx-sender)
     (current-height stacks-block-height))
    (asserts! (is-none (map-get? user-portfolios { user: user })) err-already-exists)
    (map-set user-portfolios 
      { user: user }
      {
        created-at: current-height,
        last-updated: current-height,
        total-value: u0,
        asset-count: u0
      }
    )
    (map-set user-transaction-counts { user: user } { count: u0 })
    (var-set total-users (+ (var-get total-users) u1))
    (ok true)
  )
)

(define-public (add-asset (asset-id (string-ascii 64)) (symbol (string-ascii 16)) (amount uint) (price uint))
  (let 
    ((user tx-sender)
     (current-height stacks-block-height))
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (> price u0) err-invalid-amount)
    (asserts! (is-some (map-get? user-portfolios { user: user })) err-not-found)
    
    (match (map-get? user-assets { user: user, asset-id: asset-id })
      existing-asset
      (begin
        (map-set user-assets
          { user: user, asset-id: asset-id }
          {
            symbol: symbol,
            amount: (+ (get amount existing-asset) amount),
            avg-price: (/ (+ (* (get amount existing-asset) (get avg-price existing-asset)) 
                           (* amount price)) 
                        (+ (get amount existing-asset) amount)),
            last-price: price,
            added-at: (get added-at existing-asset),
            updated-at: current-height
          }
        )
        (record-transaction asset-id "add" amount price)
        (try! (update-portfolio-value user))
        (ok true)
      )
      (begin
        (map-set user-assets
          { user: user, asset-id: asset-id }
          {
            symbol: symbol,
            amount: amount,
            avg-price: price,
            last-price: price,
            added-at: current-height,
            updated-at: current-height
          }
        )
        (record-transaction asset-id "add" amount price)
        (try! (increment-asset-count user))
        (try! (update-portfolio-value user))
        (ok true)
      )
    )
  )
)

(define-public (remove-asset (asset-id (string-ascii 64)) (amount uint))
  (let 
    ((user tx-sender)
     (current-height stacks-block-height))
    (asserts! (> amount u0) err-invalid-amount)
    (match (map-get? user-assets { user: user, asset-id: asset-id })
      existing-asset
      (begin
        (asserts! (>= (get amount existing-asset) amount) err-invalid-amount)
        (if (is-eq (get amount existing-asset) amount)
          (begin
            (map-delete user-assets { user: user, asset-id: asset-id })
            (try! (decrement-asset-count user))
          )
          (map-set user-assets
            { user: user, asset-id: asset-id }
            {
              symbol: (get symbol existing-asset),
              amount: (- (get amount existing-asset) amount),
              avg-price: (get avg-price existing-asset),
              last-price: (get last-price existing-asset),
              added-at: (get added-at existing-asset),
              updated-at: current-height
            }
          )
        )
        (record-transaction asset-id "remove" amount (get last-price existing-asset))
        (try! (update-portfolio-value user))
        (ok true)
      )
      err-not-found
    )
  )
)

(define-public (update-asset-price (asset-id (string-ascii 64)) (new-price uint))
  (let ((user tx-sender))
    (asserts! (> new-price u0) err-invalid-amount)
    (match (map-get? user-assets { user: user, asset-id: asset-id })
      existing-asset
      (begin
        (map-set user-assets
          { user: user, asset-id: asset-id }
          {
            symbol: (get symbol existing-asset),
            amount: (get amount existing-asset),
            avg-price: (get avg-price existing-asset),
            last-price: new-price,
            added-at: (get added-at existing-asset),
            updated-at: stacks-block-height
          }
        )
        (try! (update-portfolio-value user))
        (ok true)
      )
      err-not-found
    )
  )
)

(define-public (grant-view-permission (viewer principal) (expires-at (optional uint)))
  (let ((owner tx-sender))
    (asserts! (not (is-eq owner viewer)) err-unauthorized)
    (map-set portfolio-permissions
      { owner: owner, viewer: viewer }
      {
        can-view: true,
        granted-at: stacks-block-height,
        expires-at: expires-at
      }
    )
    (ok true)
  )
)

(define-public (revoke-view-permission (viewer principal))
  (let ((owner tx-sender))
    (map-delete portfolio-permissions { owner: owner, viewer: viewer })
    (ok true)
  )
)

(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u1000) err-invalid-amount)
    (var-set platform-fee-rate new-rate)
    (ok true)
  )
)

(define-private (record-transaction (asset-id (string-ascii 64)) (action (string-ascii 8)) (amount uint) (price uint))
  (let 
    ((user tx-sender)
     (tx-id (var-get next-tx-id))
     (current-count (default-to u0 (get count (map-get? user-transaction-counts { user: user })))))
    (map-set user-transactions
      { user: user, tx-id: tx-id }
      {
        asset-id: asset-id,
        action: action,
        amount: amount,
        price: price,
        timestamp: stacks-block-height,
        block-height: stacks-block-height
      }
    )
    (map-set user-transaction-counts { user: user } { count: (+ current-count u1) })
    (var-set next-tx-id (+ tx-id u1))
    true
  )
)

(define-private (update-portfolio-value (user principal))
  (match (map-get? user-portfolios { user: user })
    portfolio
    (begin
      (map-set user-portfolios
        { user: user }
        {
          created-at: (get created-at portfolio),
          last-updated: stacks-block-height,
          total-value: (calculate-total-value user),
          asset-count: (get asset-count portfolio)
        }
      )
      (ok true)
    )
    err-not-found
  )
)

(define-private (increment-asset-count (user principal))
  (match (map-get? user-portfolios { user: user })
    portfolio
    (begin
      (map-set user-portfolios
        { user: user }
        {
          created-at: (get created-at portfolio),
          last-updated: (get last-updated portfolio),
          total-value: (get total-value portfolio),
          asset-count: (+ (get asset-count portfolio) u1)
        }
      )
      (ok true)
    )
    err-not-found
  )
)

(define-private (decrement-asset-count (user principal))
  (match (map-get? user-portfolios { user: user })
    portfolio
    (begin
      (map-set user-portfolios
        { user: user }
        {
          created-at: (get created-at portfolio),
          last-updated: (get last-updated portfolio),
          total-value: (get total-value portfolio),
          asset-count: (- (get asset-count portfolio) u1)
        }
      )
      (ok true)
    )
    err-not-found
  )
)

(define-private (calculate-total-value (user principal))
  u0
)

(define-private (has-view-permission (owner principal) (viewer principal))
  (or 
    (is-eq owner viewer)
    (match (map-get? portfolio-permissions { owner: owner, viewer: viewer })
      permission
      (and 
        (get can-view permission)
        (match (get expires-at permission)
          expiry (> expiry stacks-block-height)
          true
        )
      )
      false
    )
  )
)

(define-read-only (get-portfolio (user principal))
  (map-get? user-portfolios { user: user })
)

(define-read-only (get-user-asset (user principal) (asset-id (string-ascii 64)))
  (if (has-view-permission user tx-sender)
    (ok (map-get? user-assets { user: user, asset-id: asset-id }))
    err-unauthorized
  )
)

(define-read-only (get-transaction (user principal) (tx-id uint))
  (if (has-view-permission user tx-sender)
    (ok (map-get? user-transactions { user: user, tx-id: tx-id }))
    err-unauthorized
  )
)

(define-read-only (get-transaction-count (user principal))
  (if (has-view-permission user tx-sender)
    (ok (default-to u0 (get count (map-get? user-transaction-counts { user: user }))))
    err-unauthorized
  )
)

(define-read-only (get-platform-stats)
  (ok {
    total-users: (var-get total-users),
    platform-fee-rate: (var-get platform-fee-rate),
    current-block: stacks-block-height
  })
)

(define-read-only (get-asset-metadata (asset-id (string-ascii 64)))
  (map-get? asset-metadata { asset-id: asset-id })
)
