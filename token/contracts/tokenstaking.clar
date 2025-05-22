;; Token Staking Contract

;; Error codes
(define-constant ERR-NOT-TOKEN-OWNER (err u100))
(define-constant ERR-INSUFFICIENT-TOKENS (err u101))
(define-constant ERR-STAKE-NOT-FOUND (err u102))
(define-constant ERR-LOCK-PERIOD (err u103))
(define-constant ERR-UNAUTHORIZED (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-INVALID-LOCK-PERIOD (err u106))
(define-constant ERR-INVALID-STAKE-ID (err u107))
(define-constant ERR-INVALID-TOKEN-CONTRACT (err u108))

;; FT token trait
(define-trait ft-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-balance (principal) (response uint uint))
  )
)

;; Data structures
(define-map stakes
    {staker: principal, stake-id: uint}
    {
        amount: uint,
        start-block: uint,
        lock-period: uint,
        reward-rate: uint,
        claimed: bool
    }
)

(define-map staker-info
    {staker: principal}
    {
        total-staked: uint,
        stake-count: uint
    }
)

;; Storage variables
(define-data-var next-stake-id uint u0)
(define-data-var total-staked uint u0)
(define-data-var reward-pool uint u0)

;; Helper function to validate stake ID
(define-private (is-valid-stake-id (stake-id uint))
    (and 
        (> stake-id u0)
        (<= stake-id (var-get next-stake-id))
    )
)

;; Helper function to validate amount
(define-private (is-valid-amount (amount uint))
    (> amount u0)
)

;; Helper function to validate lock period
(define-private (is-valid-lock-period (lock-period uint))
    (and 
        (>= lock-period u1)
        (<= lock-period u10000)
    )
)

;; Helper function to validate token contract
(define-private (is-valid-token-contract (token-contract <ft-trait>))
    (not (is-eq (contract-of token-contract) 'SP000000000000000000002Q6VF78.pox))
)

;; Calculate reward rate based on lock period
(define-private (calculate-reward-rate (lock-period uint))
  ;; First validate the lock period is within acceptable range
  (if (< lock-period u1)
      (err ERR-INVALID-LOCK-PERIOD)
      (if (> lock-period u10000)
          (err ERR-INVALID-LOCK-PERIOD)
          ;; If validation passes, calculate the reward rate
          (ok (if (>= lock-period u1440)
                  u10
                  (if (>= lock-period u720)
                      u5
                      u2
                  )
              )
          )
      )
  )
)

;; Stake tokens
(define-public (stake-tokens 
    (token-contract <ft-trait>)
    (amount uint)
    (lock-period uint)
)
    (begin
        ;; Validate inputs
        (asserts! (is-valid-token-contract token-contract) ERR-INVALID-TOKEN-CONTRACT)
        (asserts! (is-valid-amount amount) ERR-INVALID-AMOUNT)
        (asserts! (is-valid-lock-period lock-period) ERR-INVALID-LOCK-PERIOD)
        
        (let 
            (
                (stake-id (+ (var-get next-stake-id) u1))
                (staker tx-sender)
                (staker-data (default-to {total-staked: u0, stake-count: u0} 
                            (map-get? staker-info {staker: staker})))
                (validated-reward-rate (unwrap! (calculate-reward-rate lock-period) ERR-INVALID-LOCK-PERIOD))
                (validated-amount amount)
                (validated-lock-period lock-period)
            )
            ;; Transfer tokens to contract
            (try! (contract-call? token-contract transfer 
                validated-amount
                staker 
                (as-contract tx-sender) 
                none
            ))

            ;; Create stake entry
            (map-set stakes 
                {staker: staker, stake-id: stake-id}
                {
                    amount: validated-amount,
                    start-block: stacks-block-height,
                    lock-period: validated-lock-period,
                    reward-rate: validated-reward-rate,
                    claimed: false
                }
            )

            ;; Update staker info
            (map-set staker-info 
                {staker: staker}
                {
                    total-staked: (+ (get total-staked staker-data) validated-amount),
                    stake-count: (+ (get stake-count staker-data) u1)
                }
            )

            ;; Update global stats
            (var-set next-stake-id stake-id)
            (var-set total-staked (+ (var-get total-staked) validated-amount))

            (ok stake-id)
        )
    )
)

;; Unstake tokens
(define-public (unstake 
    (token-contract <ft-trait>)
    (stake-id uint)
)
    (begin
        ;; Validate inputs
        (asserts! (is-valid-token-contract token-contract) ERR-INVALID-TOKEN-CONTRACT)
        (asserts! (is-valid-stake-id stake-id) ERR-INVALID-STAKE-ID)
        
        (let 
            (
                (staker tx-sender)
                (validated-stake-id stake-id)
                (stake (unwrap! (map-get? stakes {staker: staker, stake-id: validated-stake-id}) ERR-STAKE-NOT-FOUND))
                (staker-data (default-to {total-staked: u0, stake-count: u0} 
                            (map-get? staker-info {staker: staker})))
                (current-block stacks-block-height)
                (lock-end-block (+ (get start-block stake) (get lock-period stake)))
                (amount (get amount stake))
                (reward (calculate-reward stake current-block))
            )
            ;; Validate lock period has ended
            (asserts! (>= current-block lock-end-block) ERR-LOCK-PERIOD)
            
            ;; Validate stake hasn't been claimed
            (asserts! (not (get claimed stake)) ERR-UNAUTHORIZED)

            ;; Mark stake as claimed
            (map-set stakes 
                {staker: staker, stake-id: validated-stake-id}
                (merge stake {claimed: true})
            )

            ;; Update staker info
            (map-set staker-info 
                {staker: staker}
                {
                    total-staked: (- (get total-staked staker-data) amount),
                    stake-count: (- (get stake-count staker-data) u1)
                }
            )

            ;; Update global stats
            (var-set total-staked (- (var-get total-staked) amount))

            ;; Transfer tokens back to staker with reward
            (as-contract 
                (try! (contract-call? token-contract transfer 
                    (+ amount reward) 
                    (as-contract tx-sender) 
                    staker 
                    none
                ))
            )

            (ok (+ amount reward))
        )
    )
)

;; Add to reward pool
(define-public (add-to-reward-pool 
    (token-contract <ft-trait>)
    (amount uint)
)
    (begin
        ;; Validate inputs
        (asserts! (is-valid-token-contract token-contract) ERR-INVALID-TOKEN-CONTRACT)
        (asserts! (is-valid-amount amount) ERR-INVALID-AMOUNT)
        
        (let
            (
                (validated-amount amount)
            )
            ;; Transfer tokens to contract
            (try! (contract-call? token-contract transfer 
                validated-amount
                tx-sender 
                (as-contract tx-sender) 
                none
            ))

            ;; Update reward pool
            (var-set reward-pool (+ (var-get reward-pool) validated-amount))

            (ok true)
        )
    )
)

;; Calculate reward for a stake
(define-private (calculate-reward (stake {amount: uint, start-block: uint, lock-period: uint, reward-rate: uint, claimed: bool}) (current-block uint))
    (let
        (
            (blocks-staked (- current-block (get start-block stake)))
            (rate (get reward-rate stake))
            (amount (get amount stake))
        )
        (/ (* amount rate blocks-staked) u10000)
    )
)

;; View functions
(define-read-only (get-stake-details (staker principal) (stake-id uint))
    (map-get? stakes {staker: staker, stake-id: stake-id})
)

(define-read-only (get-staker-info (staker principal))
    (map-get? staker-info {staker: staker})
)

(define-read-only (get-total-staked)
    (var-get total-staked)
)

(define-read-only (get-reward-pool)
    (var-get reward-pool)
)

(define-read-only (get-estimated-reward (staker principal) (stake-id uint))
    (begin
        (asserts! (is-valid-stake-id stake-id) ERR-INVALID-STAKE-ID)
        (let
            (
                (stake (unwrap! (map-get? stakes {staker: staker, stake-id: stake-id}) ERR-STAKE-NOT-FOUND))
            )
            (ok (calculate-reward stake stacks-block-height))
        )
    )
)