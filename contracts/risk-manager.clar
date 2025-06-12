;; Risk Manager Verification Contract
;; Manages verification and certification of risk management professionals

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_MANAGER_NOT_FOUND (err u101))
(define-constant ERR_MANAGER_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_REPUTATION (err u103))
(define-constant ERR_VERIFICATION_EXPIRED (err u104))
(define-constant ERR_INVALID_SPECIALTY (err u105))

;; Data Variables
(define-data-var next-manager-id uint u1)
(define-data-var contract-paused bool false)

;; Data Maps
(define-map risk-managers
  uint
  {
    principal: principal,
    name: (string-ascii 50),
    certification: (string-ascii 100),
    specialty: (string-ascii 50),
    reputation-score: uint,
    verification-date: uint,
    expiry-date: uint,
    is-active: bool,
    total-assessments: uint,
    successful-assessments: uint
  }
)

(define-map manager-by-principal principal uint)
(define-map manager-specialties (string-ascii 50) (list 100 uint))

;; Read-only functions
(define-read-only (get-manager-info (manager-id uint))
  (map-get? risk-managers manager-id)
)

(define-read-only (get-manager-by-principal (manager-principal principal))
  (match (map-get? manager-by-principal manager-principal)
    manager-id (get-manager-info manager-id)
    none
  )
)

(define-read-only (is-manager-verified (manager-id uint))
  (match (get-manager-info manager-id)
    manager-data (and
      (get is-active manager-data)
      (>= block-height (get verification-date manager-data))
      (<= block-height (get expiry-date manager-data))
    )
    false
  )
)

(define-read-only (get-managers-by-specialty (specialty (string-ascii 50)))
  (default-to (list) (map-get? manager-specialties specialty))
)

(define-read-only (calculate-success-rate (manager-id uint))
  (match (get-manager-info manager-id)
    manager-data
      (if (> (get total-assessments manager-data) u0)
        (/ (* (get successful-assessments manager-data) u100) (get total-assessments manager-data))
        u0
      )
    u0
  )
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

;; Public functions
(define-public (register-risk-manager
  (name (string-ascii 50))
  (certification (string-ascii 100))
  (specialty (string-ascii 50))
)
  (let (
    (manager-id (var-get next-manager-id))
    (current-time block-height)
    (expiry-time (+ block-height u52560)) ;; ~1 year in blocks
  )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? manager-by-principal tx-sender)) ERR_MANAGER_ALREADY_EXISTS)
    (asserts! (> (len name) u0) ERR_INVALID_SPECIALTY)

    ;; Create manager record
    (map-set risk-managers manager-id {
      principal: tx-sender,
      name: name,
      certification: certification,
      specialty: specialty,
      reputation-score: u50, ;; Starting reputation
      verification-date: current-time,
      expiry-date: expiry-time,
      is-active: true,
      total-assessments: u0,
      successful-assessments: u0
    })

    ;; Update mappings
    (map-set manager-by-principal tx-sender manager-id)

    ;; Update specialty list
    (let (
      (current-specialty-list (default-to (list) (map-get? manager-specialties specialty)))
    )
      (map-set manager-specialties specialty (unwrap! (as-max-len? (append current-specialty-list manager-id) u100) ERR_INVALID_SPECIALTY))
    )

    ;; Increment next ID
    (var-set next-manager-id (+ manager-id u1))

    (ok manager-id)
  )
)

(define-public (update-reputation (manager-id uint) (new-score uint))
  (let (
    (manager-data (unwrap! (get-manager-info manager-id) ERR_MANAGER_NOT_FOUND))
  )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) (is-eq tx-sender (get principal manager-data))) ERR_UNAUTHORIZED)
    (asserts! (<= new-score u100) ERR_INVALID_REPUTATION)

    (map-set risk-managers manager-id (merge manager-data { reputation-score: new-score }))
    (ok true)
  )
)

(define-public (renew-verification (manager-id uint))
  (let (
    (manager-data (unwrap! (get-manager-info manager-id) ERR_MANAGER_NOT_FOUND))
    (new-expiry (+ block-height u52560))
  )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get principal manager-data)) ERR_UNAUTHORIZED)

    (map-set risk-managers manager-id (merge manager-data {
      verification-date: block-height,
      expiry-date: new-expiry
    }))
    (ok true)
  )
)

(define-public (deactivate-manager (manager-id uint))
  (let (
    (manager-data (unwrap! (get-manager-info manager-id) ERR_MANAGER_NOT_FOUND))
  )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) (is-eq tx-sender (get principal manager-data))) ERR_UNAUTHORIZED)

    (map-set risk-managers manager-id (merge manager-data { is-active: false }))
    (ok true)
  )
)

(define-public (update-assessment-stats (manager-id uint) (successful bool))
  (let (
    (manager-data (unwrap! (get-manager-info manager-id) ERR_MANAGER_NOT_FOUND))
    (new-total (+ (get total-assessments manager-data) u1))
    (new-successful (if successful (+ (get successful-assessments manager-data) u1) (get successful-assessments manager-data)))
  )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    ;; This function should only be called by other contracts in the system
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)

    (map-set risk-managers manager-id (merge manager-data {
      total-assessments: new-total,
      successful-assessments: new-successful
    }))
    (ok true)
  )
)

;; Admin functions
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (emergency-deactivate-manager (manager-id uint))
  (let (
    (manager-data (unwrap! (get-manager-info manager-id) ERR_MANAGER_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)

    (map-set risk-managers manager-id (merge manager-data { is-active: false }))
    (ok true)
  )
)
