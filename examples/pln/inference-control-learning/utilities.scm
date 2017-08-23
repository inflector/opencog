;; Utilities for the inference control learning experiment

(use-modules (srfi srfi-1))
(use-modules (opencog logger))
(use-modules (opencog randgen))

;; Set a logger for the experiment
(define icl-logger (cog-new-logger))
(cog-logger-set-component! icl-logger "ICL")
(define (icl-logger-error . args) (apply cog-logger-error (cons icl-logger args)))
(define (icl-logger-warn . args) (apply cog-logger-warn (cons icl-logger args)))
(define (icl-logger-info . args) (apply cog-logger-info (cons icl-logger args)))
(define (icl-logger-debug . args) (apply cog-logger-debug (cons icl-logger args)))
(define (icl-logger-fine . args) (apply cog-logger-fine (cons icl-logger args)))

;; Let of characters of the alphabet
(define alphabet-list
  (string->list "ABCDEFGHIJKLMNOPQRSTUVWXYZ"))

;; Given a number between 0 and 25 return the corresponding letter as
;; a string.
(define (alphabet-ref i)
  (list->string (list (list-ref alphabet-list i))))

;; Randomly select between 2 ordered letters and create a target
;;
;; Inheritance
;;   X
;;   Y
(define (gen-random-target)
  (let* ((Ai (cog-randgen-randint 25))
         (Bi (+ Ai (random (- 26 Ai))))
         (A (alphabet-ref Ai))
         (B (alphabet-ref Bi)))
    (Inheritance (Concept A) (Concept B))))

;; Randomly generate N targets
(define (gen-random-targets N)
  (if (= N 0)
      '()
      (cons (gen-random-target) (gen-random-targets (- N 1)))))

;; Log the given atomspace at some level
(define (icl-logger-info-atomspace as)
  (icl-logger-info "~a" (atomspace->string as)))
(define (icl-logger-debug-atomspace as)
  (icl-logger-debug "~a" (atomspace->string as)))

;; Convert the given atomspace into a string.
(define (atomspace->string as)
  (let* ((old-as (cog-set-atomspace! as))
         ;; Get all atoms in as
         (all-atoms (get-all-atoms))
         (all-atoms-strings (map atom->string (get-all-atoms)))
         (all-atoms-string (apply string-append all-atoms-strings)))
    ;; (cog-logger-debug "types = ~a" types)
    ;; (cog-logger-debug "all-atoms (handles) = ~a" (map cog-handle all-atoms))
    (cog-set-atomspace! old-as)
    all-atoms-string))

(define (get-all-atoms)
  (apply append (map get-and-log-atoms (cog-get-types))))

(define (get-and-log-atoms type)
  (let* ((atoms (cog-get-atoms type)))
    (cog-logger-debug "get-and-log-atoms type = ~a" type)
    (cog-logger-debug "get-and-log-atoms atoms = ~a" (map cog-handle atoms))
    atoms))

;; Convert the given atom into a string if its incoming set is null,
;; otherwise the string is empty.
(define (atom->string h)
  (cog-logger-debug "(length (cog-incoming-set ~a)) = ~a"
                    (cog-handle h)
                    (length (cog-incoming-set h)))
  (cog-logger-debug "(null? (cog-incoming-set ~a)) = ~a"
                    (cog-handle h)
                    (null? (cog-incoming-set h)))
  (cog-logger-debug "h[~a] = ~a" (cog-handle h) h)
  (if (null? (cog-incoming-set h))  ; Avoid redundant
                                    ; corrections
      (format "~a" h)
      ""))

;; Remove dangling atoms from an atomspace. That is atoms with default
;; TV (null confidence) with empty incoming set
(define (remove-dangling-atoms as)
  (let* ((old-as (cog-set-atomspace! as))
         (all-atoms (apply append (map cog-get-atoms (cog-get-types)))))
    ;; (icl-logger-debug "all-atoms = ~a" all-atoms)
    (for-each remove-dangling-atom all-atoms)
    (cog-set-atomspace! old-as)))

;; Remove the atom from the current atomspace if it is dangling. That
;; is it has an empty incoming set and its TV has null confidence.
(define (remove-dangling-atom atom)
  ;; (icl-logger-debug "remove-dangling-atom atom = ~a" atom)
  (if (and (cog-atom? atom) (null? (cog-incoming-set atom)) (= 0 (tv-conf (cog-tv atom))))
      (extract-hypergraph atom)))

;; Copy all atoms from an atomspace to another atomspace
(define (cp-as src dst)
  (let ((old-as (cog-set-atomspace! src)))
    (cog-cp-all dst)
    (cog-set-atomspace! old-as)))

;; Clear a given atomspace
(define (clear-as as)
  (let ((old-as (cog-set-atomspace! as)))
    (clear)
    (cog-set-atomspace! old-as)))
