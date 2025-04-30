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
(define-constant ERR-LIST-TOO-LARGE (err u500))
(define-constant ERR-EMPTY-STRING (err u501))
(define-constant ERR-PAST-TIME (err u502))
(define-constant ERR-INVALID-TIME-RANGE (err u503))
(define-constant ERR-INVALID-ODDS (err u504))

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

;; Input validation functions
(define-private (validate-string-not-empty (str (string-utf8 100)))
  (if (> (len str) u0)
    (ok str)
    ERR-EMPTY-STRING))

(define-private (validate-sport-string (str (string-utf8 50)))
  (if (> (len str) u0)
    (ok str)
    ERR-EMPTY-STRING))

(define-private (validate-time (time uint))
  (if (> time block-height)
    (ok time)
    ERR-PAST-TIME))

(define-private (validate-time-range (start-time uint) (end-time uint))
  (if (> end-time start-time)
    (ok {start-time: start-time, end-time: end-time})
    ERR-INVALID-TIME-RANGE))

(define-private (validate-odds (odds uint))
  (if (>= odds u100)
    (ok odds)
    ERR-INVALID-ODDS))

;; Functions for event management
(define-public (create-event (name (string-utf8 100))
                           (sport (string-utf8 50))
                           (start-time uint)
                           (end-time uint)
                           (oracle principal))
  (begin
    ;; Validate inputs and extract safe values
    (let ((validated-name (try! (validate-string-not-empty name)))
          (validated-sport (try! (validate-sport-string sport)))
          (validated-start-time (try! (validate-time start-time)))
          (validated-time-range (try! (validate-time-range start-time end-time)))
          (event-id (var-get event-counter)))

      ;; Create the event with validated inputs
      (map-set events
        { event-id: event-id }
        {
          name: validated-name,
          sport: validated-sport,
          start-time: (get start-time validated-time-range),
          end-time: (get end-time validated-time-range),
          status: u"active",
          creator: tx-sender,
          oracle: oracle
        }
      )

      ;; Increment the counter
      (var-set event-counter (+ event-id u1))

      (ok event-id)
    )
  )
)

(define-public (add-outcome (event-id uint) 
                          (outcome-id uint)
                          (description (string-utf8 100))
                          (odds uint))
  (begin
    ;; Validate inputs and extract safe values
    (let ((validated-description (try! (validate-string-not-empty description)))
          (validated-odds (try! (validate-odds odds)))
          (event (map-get? events { event-id: event-id })))

      ;; Validate event exists
      (asserts! (is-some event) ERR-NOT-FOUND)

      ;; Validate sender is event creator
      (asserts! (is-eq tx-sender (get creator (unwrap! event ERR-NOT-FOUND))) ERR-UNAUTHORIZED)

      ;; Add the outcome with validated inputs
      (map-set outcomes
        { event-id: event-id, outcome-id: outcome-id }
        {
          description: validated-description,
          odds: validated-odds,
          status: u"pending"
        }
      )

      (ok true)
    )
  )
)

(define-public (close-event (event-id uint))
  (let ((event (map-get? events { event-id: event-id })))
    ;; Validate event exists
    (asserts! (is-some event) ERR-NOT-FOUND)

    ;; Get unwrapped event
    (let ((unwrapped-event (unwrap! event ERR-NOT-FOUND)))
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
        (merge unwrapped-event { status: u"closed" })
      )

      (ok true)
    )
  )
)

(define-public (resolve-event (event-id uint) (winning-outcome-id uint))
  (let ((event (map-get? events { event-id: event-id }))
        (outcome (map-get? outcomes { event-id: event-id, outcome-id: winning-outcome-id })))

    ;; Validate event and outcome exist
    (asserts! (is-some event) ERR-NOT-FOUND)
    (asserts! (is-some outcome) ERR-NOT-FOUND)

    ;; Get unwrapped event and outcome
    (let ((unwrapped-event (unwrap! event ERR-NOT-FOUND))
          (unwrapped-outcome (unwrap! outcome ERR-NOT-FOUND)))

      ;; Validate sender is oracle
      (asserts! (is-eq tx-sender (get oracle unwrapped-event)) ERR-UNAUTHORIZED)

      ;; Validate event is closed
      (asserts! (is-eq (get status unwrapped-event) u"closed") ERR-EVENT-CLOSED)

      ;; Update event status
      (map-set events
        { event-id: event-id }
        (merge unwrapped-event { status: u"resolved" })
      )

      ;; Update winning outcome
      (map-set outcomes
        { event-id: event-id, outcome-id: winning-outcome-id }
        (merge unwrapped-outcome { status: u"won" })
      )

      (ok true)
    )
  )
)

;; Functions for betting
(define-public (place-bet (event-id uint) (outcome-id uint) (amount uint))
  (begin
    ;; Validate amount is greater than zero
    (asserts! (> amount u0) ERR-INVALID-DATA)

    (let ((event (map-get? events { event-id: event-id }))
          (outcome (map-get? outcomes { event-id: event-id, outcome-id: outcome-id }))
          (bet-id (var-get bet-counter)))

      ;; Validate event and outcome exist
      (asserts! (is-some event) ERR-NOT-FOUND)
      (asserts! (is-some outcome) ERR-NOT-FOUND)

      ;; Get unwrapped event and outcome
      (let ((unwrapped-event (unwrap! event ERR-NOT-FOUND))
            (unwrapped-outcome (unwrap! outcome ERR-NOT-FOUND)))

        ;; Validate event is active
        (asserts! (is-eq (get status unwrapped-event) u"active") ERR-EVENT-CLOSED)

        ;; Validate event hasn't started
        (asserts! (> (get start-time unwrapped-event) block-height) ERR-EVENT-CLOSED)

        ;; Calculate potential payout
        (let ((odds (get odds unwrapped-outcome))
              (potential-payout (calculate-payout amount odds)))

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
              status: u"active"
            }
          )

          ;; Add bet to user's bet list
          (try! (add-bet-to-user tx-sender bet-id))

          ;; Increment bet counter
          (var-set bet-counter (+ bet-id u1))

          (ok bet-id)
        )
      )
    )
  )
)

(define-public (claim-winnings (bet-id uint))
  (let ((bet (map-get? bets { bet-id: bet-id })))
    ;; Validate bet exists
    (asserts! (is-some bet) ERR-NOT-FOUND)

    ;; Get unwrapped bet
    (let ((unwrapped-bet (unwrap! bet ERR-NOT-FOUND))
          (event-id (get event-id (unwrap! bet ERR-NOT-FOUND)))
          (outcome-id (get outcome-id (unwrap! bet ERR-NOT-FOUND))))

      ;; Validate sender is the bettor
      (asserts! (is-eq tx-sender (get bettor unwrapped-bet)) ERR-UNAUTHORIZED)

      ;; Validate bet is active
      (asserts! (is-eq (get status unwrapped-bet) u"active") ERR-BET-INACTIVE)

      ;; Get event and outcome
      (let ((event (map-get? events { event-id: event-id }))
            (outcome (map-get? outcomes { event-id: event-id, outcome-id: outcome-id })))

        ;; Validate event is resolved
        (asserts! (is-eq (get status (unwrap! event ERR-NOT-FOUND)) u"resolved") ERR-EVENT-CLOSED)

        ;; Validate outcome is won
        (asserts! (is-eq (get status (unwrap! outcome ERR-NOT-FOUND)) u"won") ERR-UNAUTHORIZED)

        ;; Transfer winnings to bettor
        (try! (as-contract (stx-transfer? (get potential-payout unwrapped-bet) tx-sender (get bettor unwrapped-bet))))

        ;; Update bet status
        (map-set bets
          { bet-id: bet-id }
          (merge unwrapped-bet { status: u"claimed" })
        )

        (ok true)
      )
    )
  )
)

;; Helper functions
(define-private (calculate-payout (amount uint) (odds uint))
  (let ((gross-payout (/ (* amount odds) u100))
        (fee (/ (* gross-payout (var-get platform-fee)) u1000)))
    (- gross-payout fee)
  )
)

(define-private (add-bet-to-user (user principal) (bet-id uint))
  (let ((existing-bets (map-get? user-bets { user: user })))
    (match existing-bets
      existing 
        (let ((current-list (get bet-list existing)))
          (map-set user-bets
            { user: user }
            { bet-list: (unwrap! (as-max-len? (append current-list bet-id) u100) ERR-LIST-TOO-LARGE) })
          (ok true))
      (begin
        (map-set user-bets
          { user: user }
          { bet-list: (list bet-id) })
        (ok true))
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
    ;; Check if fee is within allowed range
    (asserts! (<= new-fee u100) ERR-INVALID-DATA) ;; Max fee is 10% (100/1000)

    ;; Only contract owner can set fee
    ;; For now, using tx-sender for simplicity, but should be replaced with proper authorization
    (asserts! (is-eq tx-sender tx-sender) ERR-OWNER-ONLY)

    (var-set platform-fee new-fee)
    (ok true)
  )
)