;; ChatLang DSL for chat authoring rules
;;
;; This is the custom action selector that allows OpenPsi to find the authored
;; rules.
;; TODO: This is not needed in the long run as the default action selector in
;; OpenPsi should be able to know how and what kinds of rules it should be
;; looking for at a particular point in time.

(use-modules (opencog logger)
             (opencog exec))

(define-public (chat-find-rules SENT)
  "The action selector. It first searches for the rules using DualLink,
   and then does the filtering by evaluating the context of the rules.
   Eventually returns a list of weighted rules that can satisfy the demand."
  (let* ((sent-seqs (sent-get-word-seqs SENT))
         (input-lseq (list-ref sent-seqs 2))
         (input-lset (list-ref sent-seqs 3))
         ; The ones that contains no variables/globs
         (exact-match (filter psi-rule?
           (append-map cog-get-trunk (list input-lseq input-lset))))
         ; The ones that contains no constant terms
         (no-const (filter psi-rule? (append-map cog-get-trunk
           (cog-chase-link 'MemberLink 'ListLink chatlang-no-constant))))
         ; The ones found by the recognizer
         (dual-match (filter psi-rule? (append-map cog-get-trunk
           (append (cog-outgoing-set (cog-execute! (Dual input-lseq)))
                   (cog-outgoing-set (cog-execute! (Dual input-lset)))))))
         ; Get the psi-rules associate with them
         (rules-matched (append exact-match no-const dual-match)))

        (cog-logger-debug chatlang-logger "For input:\n~a" input-lseq)
        (cog-logger-debug chatlang-logger "Rules with no constant:\n~a" no-const)
        (cog-logger-debug chatlang-logger "Exact match:\n~a" exact-match)
        (cog-logger-debug chatlang-logger "Dual match:\n~a" dual-match)
        (cog-logger-debug chatlang-logger "Rules matched:\n~a" rules-matched)

        ; TODO: Pick the one with the highest weight
        (List (append-map
          ; TODO: "psi-satisfiable?" doesn't work here (?)
          (lambda (r)
            (if (equal? (stv 1 1)
                        (cog-evaluate! (car (psi-get-context r))))
                (list r)
                '()))
          rules-matched))))

(Define
  (DefinedSchema "Get Current Input")
  (Get (State chatlang-anchor
              (Variable "$x"))))

(Define
  (DefinedSchema "Find Chat Rules")
  (Lambda (VariableList (TypedVariable (Variable "sentence")
                                       (Type "SentenceNode")))
          (ExecutionOutput (GroundedSchema "scm: chat-find-rules")
                           (List (Variable "sentence")))))

; The action selector for OpenPsi
(psi-set-action-selector
  (Put (DefinedSchema "Find Chat Rules")
       (DefinedSchema "Get Current Input"))
  default-topic)

; -----
; For debugging only
(use-modules (opencog nlp chatbot) (opencog eva-behavior))

(define-public (test-chatlang TXT)
  "Try to find (and execute) the matching rules given an input TXT."
  (define sent (car (nlp-parse TXT)))
  (State (Anchor "Chatlang: Currently Processing") sent)
  (map (lambda (r) (cog-evaluate! (gdar r)))
       (cog-outgoing-set (chat-find-rules sent))))
