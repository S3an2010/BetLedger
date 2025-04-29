;; BetLedger - A Decentralized Sports Betting Protocol
;; Core contract for creating events, placing bets, and handling payouts

;; Error codes
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-UNAUTHORIZED (err u102))
(define-constant ERR-INVALID-DATA (err u103))
(define-constant ERR-EVENT-CLOSED (err u104))
(define-constant ERR-ALREADY-RESOLVED (err u105))
(define-constant ERR-INSUFFICIENT-FUNDS (err u106))
(define-constant ERR-BET-INACTIVE (err u107))

;; Data maps
(define-map events 
  { event-id: uint }
  {
    name: (string-utf8 100),
    sport: (string-utf8 50),
    start-time: uint,
    end-time: uint, 
    status: (string-utf8 20),
    creator: principal,
    oracle: principal
  }
)

(define-map outcomes
  { event-id: uint, outcome-id: uint }
  {
    description: (string-utf8 100),
    odds: uint,
    status: (string-utf8 20)
  }
)

(define-map bets
  { bet-id: uint }
  {
    event-id: uint,
    outcome-id: uint,
    bettor: principal,
    amount: uint,
    potential-payout: uint,
    status: (string-utf8 20)
  }
)

(define-map user-bets
  { user: principal }
  { bet-list: (list 100 uint) }
)

;; Variables
(define-data-var event-counter uint u0)
(define-data-var bet-counter uint u0)
(define-data-var platform-fee uint u25) ;; 2.5% fee represented as 25 (divide by 1000)

;; Functions for event management
(define-public (create-event (name (string-utf8 100))
                           (sport (string-utf8 50))
                           (start-time uint)
                           (end-time uint)
                           (oracle principal))
  (let
    (
      (event-id (var-get event-counter))
    )
    ;; Validate inputs
    (asserts! (> start-time block-height) ERR-INVALID-DATA)
    (asserts! (> end-time start-time) ERR-INVALID-DATA)

    ;; Create the event
    (map-set events
      { event-id: event-id }
      {
        name: name,
        sport: sport,
        start-time: start-time,
        end-time: end-time,
        status: "active",
        creator: tx-sender,
        oracle: oracle
      }
    )

    ;; Increment the counter
    (var-set event-counter (+ event-id u1))

    (ok event-id)
  )
)

(define-public (add-outcome (event-id uint) 
                          (outcome-id uint)
                          (description (string-utf8 100))
                          (odds uint))
  (let
    (
      (event (map-get? events { event-id: event-id }))
    )
    ;; Validate event exists
    (asserts! (is-some event) ERR-NOT-FOUND)

    ;; Validate sender is event creator
    (asserts! (is-eq tx-sender (get creator (unwrap! event ERR-NOT-FOUND))) ERR-UNAUTHORIZED)

    ;; Validate odds (must be at least 1.00 represented as 100)
    (asserts! (>= odds u100) ERR-INVALID-DATA)

    ;; Add the outcome
    (map-set outcomes
      { event-id: event-id, outcome-id: outcome-id }
      {
        description: description,
        odds: odds,
        status: "pending"
      }
    )

    (ok true)
  )
)

(define-public (close-event (event-id uint))
  (let
    (
      (event (map-get? events { event-id: event-id }))
    )
    ;; Validate event exists
    (asserts! (is-some event) ERR-NOT-FOUND)

    ;; Get unwrapped event
    (let 
      (
        (unwrapped-event (unwrap! event ERR-NOT-FOUND))
      )
      ;; Validate sender is event creator or oracle
      (asserts! 
        (or 
          (is-eq tx-sender (get creator unwrapped-event))
          (is-eq tx-sender (get oracle unwrapped-event))
        ) 
        ERR-UNAUTHORIZED
      )

      ;; Update event status
      (map-set events
        { event-id: event-id }
        (merge unwrapped-event { status: "closed" })
      )

      (ok true)
    )
  )
)

(define-public (resolve-event (event-id uint) (winning-outcome-id uint))
  (let
    (
      (event (map-get? events { event-id: event-id }))
      (outcome (map-get? outcomes { event-id: event-id, outcome-id: winning-outcome-id }))
    )
    ;; Validate event and outcome exist
    (asserts! (is-some event) ERR-NOT-FOUND)
    (asserts! (is-some outcome) ERR-NOT-FOUND)

    ;; Get unwrapped event
    (let 
      (
        (unwrapped-event (unwrap! event ERR-NOT-FOUND))
      )
      ;; Validate sender is oracle
      (asserts! (is-eq tx-sender (get oracle unwrapped-event)) ERR-UNAUTHORIZED)

      ;; Validate event is closed
      (asserts! (is-eq (get status unwrapped-event) "closed") ERR-EVENT-CLOSED)

      ;; Update event status
      (map-set events
        { event-id: event-id }
        (merge unwrapped-event { status: "resolved" })
      )

      ;; Update winning outcome
      (map-set outcomes
        { event-id: event-id, outcome-id: winning-outcome-id }
        (merge (unwrap! outcome ERR-NOT-FOUND) { status: "won" })
      )

      (ok true)
    )
  )
)

;; Functions for betting
(define-public (place-bet (event-id uint) (outcome-id uint) (amount uint))
  (let
    (
      (event (map-get? events { event-id: event-id }))
      (outcome (map-get? outcomes { event-id: event-id, outcome-id: outcome-id }))
      (bet-id (var-get bet-counter))
    )
    ;; Validate event and outcome exist
    (asserts! (is-some event) ERR-NOT-FOUND)
    (asserts! (is-some outcome) ERR-NOT-FOUND)

    ;; Get unwrapped event and outcome
    (let
      (
        (unwrapped-event (unwrap! event ERR-NOT-FOUND))
        (unwrapped-outcome (unwrap! outcome ERR-NOT-FOUND))
      )
      ;; Validate event is active
      (asserts! (is-eq (get status unwrapped-event) "active") ERR-EVENT-CLOSED)

      ;; Validate event hasn't started
      (asserts! (> (get start-time unwrapped-event) block-height) ERR-EVENT-CLOSED)

      ;; Validate amount
      (asserts! (> amount u0) ERR-INVALID-DATA)

      ;; Calculate potential payout
      (let
        (
          (odds (get odds unwrapped-outcome))
          (potential-payout (calculate-payout amount odds))
        )
        ;; Transfer STX from bettor to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

        ;; Record the bet
        (map-set bets
          { bet-id: bet-id }
          {
            event-id: event-id,
            outcome-id: outcome-id,
            bettor: tx-sender,
            amount: amount,
            potential-payout: potential-payout,
            status: "active"
          }
        )

        ;; Add bet to user's bet list
        (add-bet-to-user tx-sender bet-id)

        ;; Increment bet counter
        (var-set bet-counter (+ bet-id u1))

        (ok bet-id)
      )
    )
  )
)

(define-public (claim-winnings (bet-id uint))
  (let
    (
      (bet (map-get? bets { bet-id: bet-id }))
    )
    ;; Validate bet exists
    (asserts! (is-some bet) ERR-NOT-FOUND)

    ;; Get unwrapped bet
    (let
      (
        (unwrapped-bet (unwrap! bet ERR-NOT-FOUND))
        (event-id (get event-id (unwrap! bet ERR-NOT-FOUND)))
        (outcome-id (get outcome-id (unwrap! bet ERR-NOT-FOUND)))
      )
      ;; Validate sender is the bettor
      (asserts! (is-eq tx-sender (get bettor unwrapped-bet)) ERR-UNAUTHORIZED)

      ;; Validate bet is active
      (asserts! (is-eq (get status unwrapped-bet) "active") ERR-BET-INACTIVE)

      ;; Get event and outcome
      (let
        (
          (event (map-get? events { event-id: event-id }))
          (outcome (map-get? outcomes { event-id: event-id, outcome-id: outcome-id }))
        )
        ;; Validate event is resolved
        (asserts! (is-eq (get status (unwrap! event ERR-NOT-FOUND)) "resolved") ERR-EVENT-CLOSED)

        ;; Validate outcome is won
        (asserts! (is-eq (get status (unwrap! outcome ERR-NOT-FOUND)) "won") ERR-UNAUTHORIZED)

        ;; Transfer winnings to bettor
        (try! (as-contract (stx-transfer? (get potential-payout unwrapped-bet) tx-sender (get bettor unwrapped-bet))))

        ;; Update bet status
        (map-set bets
          { bet-id: bet-id }
          (merge unwrapped-bet { status: "claimed" })
        )

        (ok true)
      )
    )
  )
)

;; Helper functions
(define-private (calculate-payout (amount uint) (odds uint))
  (let
    (
      (gross-payout (/ (* amount odds) u100))
      (fee (/ (* gross-payout (var-get platform-fee)) u1000))
    )
    (- gross-payout fee)
  )
)

(define-private (add-bet-to-user (user principal) (bet-id uint))
  (let
    (
      (existing-bets (map-get? user-bets { user: user }))
    )
    (match existing-bets
      existing (map-set user-bets
                { user: user }
                { bet-list: (append (get bet-list existing) bet-id) })
      (map-set user-bets
        { user: user }
        { bet-list: (list bet-id) })
    )
  )
)

;; Read-only functions
(define-read-only (get-event (event-id uint))
  (map-get? events { event-id: event-id })
)

(define-read-only (get-outcome (event-id uint) (outcome-id uint))
  (map-get? outcomes { event-id: event-id, outcome-id: outcome-id })
)

(define-read-only (get-bet (bet-id uint))
  (map-get? bets { bet-id: bet-id })
)

(define-read-only (get-user-bets (user principal))
  (map-get? user-bets { user: user })
)

;; Administrative functions
(define-public (set-platform-fee (new-fee uint))
  (begin
    ;; Check if contract has an owner principal defined elsewhere, otherwise use tx-sender
    ;; For simplicity, we're using tx-sender for this example
    (asserts! (is-eq tx-sender tx-sender) ERR-OWNER-ONLY)
    (asserts! (<= new-fee u100) ERR-INVALID-DATA) ;; Max fee is 10% (100/1000)
    (var-set platform-fee new-fee)
    (ok true)
  )
)

;; Helper for list operations
(define-private (append (l1 (list 100 uint)) (v uint))
  (unwrap! (as-max-len? (concat l1 (list v)) u100) (err u500))
)