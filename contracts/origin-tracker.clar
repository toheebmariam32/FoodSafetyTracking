;; Origin Tracker Contract
;; Tracks food products from farm or production facility through the supply chain
;; Provides comprehensive traceability and food safety monitoring

;; Error constants
(define-constant ERR-NOT-FOUND (err u100))
(define-constant ERR-UNAUTHORIZED (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-PRODUCT (err u103))
(define-constant ERR-INVALID-BATCH (err u104))
(define-constant ERR-EXPIRED-PRODUCT (err u105))
(define-constant ERR-CONTAMINATED (err u106))

;; Data variables
(define-data-var next-product-id uint u1)
(define-data-var next-batch-id uint u1)
(define-data-var contract-owner principal tx-sender)

;; Product information structure
(define-map products
  { product-id: uint }
  {
    name: (string-ascii 100),
    producer: principal,
    origin-location: (string-ascii 200),
    production-date: uint,
    expiry-date: uint,
    product-type: (string-ascii 50),
    organic-certified: bool,
    created-at: uint,
    is-active: bool
  }
)

;; Batch tracking for products
(define-map batches
  { batch-id: uint }
  {
    product-id: uint,
    batch-number: (string-ascii 50),
    quantity: uint,
    temperature-range: { min: int, max: int },
    storage-conditions: (string-ascii 100),
    quality-score: uint,
    is-recalled: bool,
    created-at: uint
  }
)

;; Supply chain tracking events
(define-map supply-chain-events
  { event-id: uint }
  {
    product-id: uint,
    batch-id: uint,
    event-type: (string-ascii 50),
    location: (string-ascii 200),
    handler: principal,
    temperature: int,
    humidity: uint,
    notes: (string-ascii 500),
    timestamp: uint
  }
)

;; Quality checkpoints
(define-map quality-checks
  { check-id: uint }
  {
    product-id: uint,
    batch-id: uint,
    inspector: principal,
    check-type: (string-ascii 50),
    result: (string-ascii 20),
    score: uint,
    contamination-detected: bool,
    notes: (string-ascii 300),
    timestamp: uint
  }
)

;; Event tracking counters
(define-data-var next-event-id uint u1)
(define-data-var next-check-id uint u1)

;; Authorized handlers for supply chain operations
(define-map authorized-handlers
  { handler: principal }
  { authorized: bool, role: (string-ascii 50) }
)

;; Public function to register a new food product
(define-public (register-product 
  (name (string-ascii 100))
  (origin-location (string-ascii 200))
  (expiry-date uint)
  (product-type (string-ascii 50))
  (organic-certified bool))
  (let 
    (
      (product-id (var-get next-product-id))
      (current-time stacks-block-height)
    )
    (map-set products
      { product-id: product-id }
      {
        name: name,
        producer: tx-sender,
        origin-location: origin-location,
        production-date: current-time,
        expiry-date: expiry-date,
        product-type: product-type,
        organic-certified: organic-certified,
        created-at: current-time,
        is-active: true
      }
    )
    (var-set next-product-id (+ product-id u1))
    (ok product-id)
  )
)

;; Public function to create a new batch for a product
(define-public (create-batch
  (product-id uint)
  (batch-number (string-ascii 50))
  (quantity uint)
  (min-temp int)
  (max-temp int)
  (storage-conditions (string-ascii 100)))
  (let
    (
      (batch-id (var-get next-batch-id))
      (current-time stacks-block-height)
    )
    (asserts! (is-some (map-get? products { product-id: product-id })) ERR-INVALID-PRODUCT)
    (map-set batches
      { batch-id: batch-id }
      {
        product-id: product-id,
        batch-number: batch-number,
        quantity: quantity,
        temperature-range: { min: min-temp, max: max-temp },
        storage-conditions: storage-conditions,
        quality-score: u100,
        is-recalled: false,
        created-at: current-time
      }
    )
    (var-set next-batch-id (+ batch-id u1))
    (ok batch-id)
  )
)

;; Public function to record supply chain event
(define-public (record-supply-chain-event
  (product-id uint)
  (batch-id uint)
  (event-type (string-ascii 50))
  (location (string-ascii 200))
  (temperature int)
  (humidity uint)
  (notes (string-ascii 500)))
  (let
    (
      (event-id (var-get next-event-id))
      (current-time stacks-block-height)
    )
    (asserts! (is-some (map-get? products { product-id: product-id })) ERR-INVALID-PRODUCT)
    (asserts! (is-some (map-get? batches { batch-id: batch-id })) ERR-INVALID-BATCH)
    (map-set supply-chain-events
      { event-id: event-id }
      {
        product-id: product-id,
        batch-id: batch-id,
        event-type: event-type,
        location: location,
        handler: tx-sender,
        temperature: temperature,
        humidity: humidity,
        notes: notes,
        timestamp: current-time
      }
    )
    (var-set next-event-id (+ event-id u1))
    (ok event-id)
  )
)

;; Public function to perform quality check
(define-public (perform-quality-check
  (product-id uint)
  (batch-id uint)
  (check-type (string-ascii 50))
  (result (string-ascii 20))
  (score uint)
  (contamination-detected bool)
  (notes (string-ascii 300)))
  (let
    (
      (check-id (var-get next-check-id))
      (current-time stacks-block-height)
    )
    (asserts! (is-some (map-get? products { product-id: product-id })) ERR-INVALID-PRODUCT)
    (asserts! (is-some (map-get? batches { batch-id: batch-id })) ERR-INVALID-BATCH)
    (map-set quality-checks
      { check-id: check-id }
      {
        product-id: product-id,
        batch-id: batch-id,
        inspector: tx-sender,
        check-type: check-type,
        result: result,
        score: score,
        contamination-detected: contamination-detected,
        notes: notes,
        timestamp: current-time
      }
    )
    (var-set next-check-id (+ check-id u1))
    (if contamination-detected
      (begin
        (try! (recall-batch batch-id))
        (ok check-id)
      )
      (ok check-id)
    )
  )
)

;; Public function to recall a batch
(define-public (recall-batch (batch-id uint))
  (let
    (
      (batch (unwrap! (map-get? batches { batch-id: batch-id }) ERR-INVALID-BATCH))
    )
    (map-set batches
      { batch-id: batch-id }
      (merge batch { is-recalled: true })
    )
    (ok true)
  )
)

;; Public function to authorize supply chain handlers
(define-public (authorize-handler (handler principal) (role (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (map-set authorized-handlers
      { handler: handler }
      { authorized: true, role: role }
    )
    (ok true)
  )
)

;; Read-only function to get product information
(define-read-only (get-product (product-id uint))
  (map-get? products { product-id: product-id })
)

;; Read-only function to get batch information
(define-read-only (get-batch (batch-id uint))
  (map-get? batches { batch-id: batch-id })
)

;; Read-only function to get supply chain event
(define-read-only (get-supply-chain-event (event-id uint))
  (map-get? supply-chain-events { event-id: event-id })
)

;; Read-only function to get quality check
(define-read-only (get-quality-check (check-id uint))
  (map-get? quality-checks { check-id: check-id })
)

;; Read-only function to check if product is expired
(define-read-only (is-product-expired (product-id uint))
  (let
    (
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
      (current-time stacks-block-height)
    )
    (ok (>= current-time (get expiry-date product)))
  )
)

;; Read-only function to check if batch is recalled
(define-read-only (is-batch-recalled (batch-id uint))
  (let
    (
      (batch (unwrap! (map-get? batches { batch-id: batch-id }) ERR-INVALID-BATCH))
    )
    (ok (get is-recalled batch))
  )
)

;; Read-only function to get next product ID
(define-read-only (get-next-product-id)
  (ok (var-get next-product-id))
)

;; Read-only function to get contract owner
(define-read-only (get-contract-owner)
  (ok (var-get contract-owner))
)
