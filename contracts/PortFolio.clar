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
(define-data-var total-portfolio-value uint u0)
(define-data-var snapshot-interval uint u144)

(define-map portfolio-snapshots
  { user: principal, snapshot-id: uint }
  {
    timestamp: uint,
    total-value: uint,
    cost-basis: uint,
    pnl: int,
    pnl-percentage: int
  }
)

(define-map user-snapshot-counts
  { user: principal }
  { count: uint }
)

(define-map asset-performance
  { user: principal, asset-id: (string-ascii 64) }
  {
    total-cost: uint,
    current-value: uint,
    pnl: int,
    pnl-percentage: int,
    last-calculated: uint
  }
)

(define-map user-last-snapshot
  { user: principal }
  { block-height: uint }
)

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
    (map-set user-snapshot-counts { user: user } { count: u0 })
    (map-set user-last-snapshot { user: user } { block-height: u0 })
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
        (try! (update-asset-performance asset-id))
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
        (try! (update-asset-performance asset-id))
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
        (if (is-some (map-get? user-assets { user: user, asset-id: asset-id }))
          (try! (update-asset-performance asset-id))
          true
        )
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
        (try! (update-asset-performance asset-id))
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
  (default-to u0 (get total-value (map-get? user-portfolios { user: user })))
)

(define-private (calculate-cost-basis (user principal))
  (let 
    ((result (fold calculate-single-asset-cost 
                  (list "STX" "BTC" "ETH" "USDC" "ALEX" "DIKO" "XBTC" "sBTC" "WELSH" "CHA") 
                  { user: user, total: u0 })))
    (get total result)
  )
)

(define-private (calculate-single-asset-cost (asset-id (string-ascii 64)) (acc { user: principal, total: uint }))
  (match (map-get? user-assets { user: (get user acc), asset-id: asset-id })
    asset-data
    { user: (get user acc), total: (+ (get total acc) (* (get amount asset-data) (get avg-price asset-data))) }
    acc
  )
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

(define-public (create-portfolio-snapshot)
  (let 
    ((user tx-sender)
     (current-height stacks-block-height)
     (last-snapshot (get block-height (default-to { block-height: u0 } (map-get? user-last-snapshot { user: user }))))
     (snapshot-count (default-to u0 (get count (map-get? user-snapshot-counts { user: user }))))
     (current-value (calculate-total-value user))
     (cost-basis (calculate-cost-basis user))
     (pnl (- (to-int current-value) (to-int cost-basis)))
     (pnl-pct (if (> cost-basis u0) (/ (* pnl 10000) (to-int cost-basis)) 0)))
    
    (asserts! (is-some (map-get? user-portfolios { user: user })) err-not-found)
    (asserts! (>= (- current-height last-snapshot) (var-get snapshot-interval)) err-unauthorized)
    
    (map-set portfolio-snapshots
      { user: user, snapshot-id: snapshot-count }
      {
        timestamp: current-height,
        total-value: current-value,
        cost-basis: cost-basis,
        pnl: pnl,
        pnl-percentage: pnl-pct
      }
    )
    
    (map-set user-snapshot-counts { user: user } { count: (+ snapshot-count u1) })
    (map-set user-last-snapshot { user: user } { block-height: current-height })
    (ok snapshot-count)
  )
)

(define-public (update-asset-performance (asset-id (string-ascii 64)))
  (let 
    ((user tx-sender)
     (current-height stacks-block-height))
    
    (match (map-get? user-assets { user: user, asset-id: asset-id })
      asset-data
      (let 
        ((total-cost (* (get amount asset-data) (get avg-price asset-data)))
         (current-value (* (get amount asset-data) (get last-price asset-data)))
         (pnl (- (to-int current-value) (to-int total-cost)))
         (pnl-pct (if (> total-cost u0) (/ (* pnl 10000) (to-int total-cost)) 0)))
        
        (map-set asset-performance
          { user: user, asset-id: asset-id }
          {
            total-cost: total-cost,
            current-value: current-value,
            pnl: pnl,
            pnl-percentage: pnl-pct,
            last-calculated: current-height
          }
        )
        (ok true)
      )
      err-not-found
    )
  )
)

(define-read-only (get-portfolio-performance (user principal))
  (if (has-view-permission user tx-sender)
    (let 
      ((current-value (calculate-total-value user))
       (cost-basis (calculate-cost-basis user))
       (pnl (- (to-int current-value) (to-int cost-basis)))
       (pnl-pct (if (> cost-basis u0) (/ (* pnl 10000) (to-int cost-basis)) 0)))
      (ok {
        total-value: current-value,
        cost-basis: cost-basis,
        unrealized-pnl: pnl,
        pnl-percentage: pnl-pct,
        calculated-at: stacks-block-height
      })
    )
    err-unauthorized
  )
)

(define-read-only (get-asset-performance (user principal) (asset-id (string-ascii 64)))
  (if (has-view-permission user tx-sender)
    (ok (map-get? asset-performance { user: user, asset-id: asset-id }))
    err-unauthorized
  )
)

(define-read-only (get-portfolio-snapshot (user principal) (snapshot-id uint))
  (if (has-view-permission user tx-sender)
    (ok (map-get? portfolio-snapshots { user: user, snapshot-id: snapshot-id }))
    err-unauthorized
  )
)

(define-read-only (get-snapshot-count (user principal))
  (if (has-view-permission user tx-sender)
    (ok (default-to u0 (get count (map-get? user-snapshot-counts { user: user }))))
    err-unauthorized
  )
)

(define-read-only (compare-snapshots (user principal) (snapshot-id-1 uint) (snapshot-id-2 uint))
  (if (has-view-permission user tx-sender)
    (match (map-get? portfolio-snapshots { user: user, snapshot-id: snapshot-id-1 })
      snap1
      (match (map-get? portfolio-snapshots { user: user, snapshot-id: snapshot-id-2 })
        snap2
        (let 
          ((value-change (- (to-int (get total-value snap2)) (to-int (get total-value snap1))))
           (pnl-change (- (get pnl snap2) (get pnl snap1)))
           (time-diff (- (get timestamp snap2) (get timestamp snap1))))
          (ok {
            period-blocks: time-diff,
            value-change: value-change,
            pnl-change: pnl-change,
            performance-trend: (if (> value-change 0) "up" "down")
          })
        )
        err-not-found
      )
      err-not-found
    )
    err-unauthorized
  )
)

(define-read-only (get-roi (user principal))
  (if (has-view-permission user tx-sender)
    (let 
      ((cost-basis (calculate-cost-basis user))
       (current-value (calculate-total-value user)))
      (if (> cost-basis u0)
        (ok (/ (* (- (to-int current-value) (to-int cost-basis)) 10000) (to-int cost-basis)))
        (ok 0)
      )
    )
    err-unauthorized
  )
)
