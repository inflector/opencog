;; ChatLang DSL for chat authoring rules
;;
;; Assorted functions for translating individual terms into Atomese fragments.

(use-modules (ice-9 optargs))
(use-modules (opencog exec))

; ----------
; Helper functions

(define (genvar STR is-literal?)
  "Helper function for generating the name of a VariableNode,
   so as to make it slightly easier for a human to debug the code.
   is-literal? flag is for indicating whether this variable
   or glob is supposed to go to the word-seq or lemma-seq."
  (if is-literal?
      (string-append STR "-" (choose-var-name))
      (string-append (get-lemma STR) "-" (choose-var-name))))

(define (term-length TERMS)
  "Helper function to find the maximum number of words one of
   the TERMS has, for setting the upper bound of the GlobNode."
  (fold
    (lambda (term len)
      (let ((tl (cond ((equal? 'phrase (car term))
                       (length (string-split (cdr term) #\sp)))
                      ((equal? 'concept (car term))
                       (concept-length (Concept (cdr term))))
                      (else 1))))
           (max len tl)))
    0
    TERMS))

(define (concept-length CONCEPT)
  "Helper function to find the maximum number of words CONCEPT has."
  (define c (cog-outgoing-set (cog-execute!
              (Get (Reference (Variable "$x") CONCEPT)))))
  (if (null? c)
      -1  ; This may happen if the concept is not yet defined in the system...
      (fold (lambda (term len)
        (let ((tl (cond ((equal? 'PhraseNode (cog-type term))
                         (length (string-split (cog-name term) #\sp)))
                        ((equal? 'ConceptNode (cog-type term))
                         (concept-length term))
                        (else 1))))
             (max tl len)))
        0
        c)))

(define (terms-to-atomese TERMS)
  "Helper function to convert a list of terms into atomese.
   For use of choices and negation."
  (map (lambda (t)
    (cond ((equal? 'word (car t))
           (WordNode (cdr t)))
          ((equal? 'lemma (car t))
           (LemmaNode (get-lemma (cdr t))))
          ((equal? 'phrase (car t))
           (PhraseNode (cdr t)))
          ((equal? 'concept (car t))
           (Concept (cdr t)))
          (else (feature-not-supported (car t) (cdr t)))))
       TERMS))

; ----------
; The terms

(define (word STR)
  "Literal word occurrence."
  (let* ((v1 (Variable (genvar STR #t)))
         (v2 (Variable (genvar STR #f)))
         (l (WordNode (get-lemma STR)))
         (v (list (TypedVariable v1 (Type "WordNode"))
                  (TypedVariable v2 (Type "WordInstanceNode"))))
         (c (list (ReferenceLink v2 v1)
                  (WordInstanceLink v2 (Variable "$P"))
                  (ReferenceLink v2 (WordNode STR)))))
    (list v c (list v1) (list l))))

(define (lemma STR)
  "Lemma occurrence, aka canonical form of a term.
   This is the default for word mentions in the rule pattern."
  (let* ((v1 (Variable (genvar STR #t)))
         (v2 (Variable (genvar STR #f)))
         (l (WordNode (get-lemma STR)))
         (v (list (TypedVariable v1 (Type "WordNode"))
                  (TypedVariable v2 (Type "WordInstanceNode"))))
         ; Note: This converts STR to its lemma
         (c (list (ReferenceLink v2 v1)
                  (LemmaLink v2 l)
                  (WordInstanceLink v2 (Variable "$P")))))
    (list v c (list v1) (list l))))

(define (phrase STR)
  "Occurrence of a phrase or a group of words.
   All the words are assumed to be literal / non-canonical."
  (fold (lambda (wd lst)
                (list (append (car lst) (car wd))
                      (append (cadr lst) (cadr wd))
                      (append (caddr lst) (caddr wd))
                      (append (cadddr lst) (cadddr wd))))
        (list '() '() '() '())
        (map word (string-split STR #\sp))))

(define* (concept STR)
  "Occurrence of a concept."
  (let ((g1 (Glob (genvar STR #t)))
        (g2 (Glob (genvar STR #f)))
        (clength (concept-length (Concept STR))))
    (list (list (TypedVariable g1 (TypeSet (Type "WordNode")
                                           (Interval (Number 1)
                                                     (Number clength))))
                (TypedVariable g2 (TypeSet (Type "WordNode")
                                           (Interval (Number 1)
                                                     (Number clength)))))
          (list (Evaluation (GroundedPredicate "scm: chatlang-concept?")
                            (List (Concept STR) g1)))
          (list g1)
          (list g2))))

(define* (choices TERMS)
  "Occurrence of a list of choices. Existence of either one of
   the words/lemmas/phrases/concepts in the list will be considered
   as a match."
  (let ((g1 (Glob (genvar "choices" #t)))
        (g2 (Glob (genvar "choices" #f)))
        (tlength (term-length TERMS)))
    (list (list (TypedVariable g1 (TypeSet (Type "WordNode")
                                           (Interval (Number 1)
                                                     (Number tlength))))
                (TypedVariable g2 (TypeSet (Type "WordNode")
                                           (Interval (Number 1)
                                                     (Number tlength)))))
          (list (Evaluation (GroundedPredicate "scm: chatlang-choices?")
                            (List (List (terms-to-atomese TERMS)) g1)))
          (list g1)
          (list g2))))

(define (negation TERMS)
  "Absent of a term or a list of terms (words/phrases/concepts)."
  (list '()  ; No variable declaration
        (list (Evaluation (GroundedPredicate "scm: chatlang-negation?")
                          (List (terms-to-atomese TERMS))))
        ; Nothing for the word-seq and lemma-seq
        '() '()))

(define* (wildcard LOWER UPPER)
  "Occurrence of a wildcard that the number of atoms to be matched
   can be restricted.
   Note: -1 in the upper bound means infinity."
  (let* ((g1 (Glob (genvar "wildcard" #t)))
         (g2 (Glob (genvar "wildcard" #f))))
    (list (list (TypedVariable g1
                (TypeSet (Type "WordNode")
                         (Interval (Number LOWER) (Number UPPER))))
                (TypedVariable g2
                (TypeSet (Type "WordNode")
                         (Interval (Number LOWER) (Number UPPER)))))
        '()
        (list g1)
        (list g2))))

(define (variable VAR WGRD LGRD)
  "Occurence of a variable. The value grounded for it needs to be recorded.
   VAR is the variable name.
   WGRD and LGRD can either be a VariableNode or a GlobNode, which pass
   the actual value grounded for it in original words and lemmas at runtime."
  (Evaluation (GroundedPredicate "scm: chatlang-record-groundings")
    (List (List (chatlang-var-word VAR) WGRD)
          (List (chatlang-var-lemma VAR) LGRD))))

(define (context-function NAME ARGS)
  "Occurrence of a function in the context of a rule."
  (Evaluation (GroundedPredicate (string-append "scm: " NAME))
              (List ARGS)))

(define (action-function NAME ARGS)
  "Occurrence of a function in the action of a rule."
  (ExecutionOutput (GroundedSchema (string-append "scm: " NAME))
                   (List ARGS)))

(define (action-choices ACTIONS)
  "Pick one of the ACTIONS."
  (ExecutionOutput (GroundedSchema "scm: chatlang-pick-action")
                   (Set ACTIONS)))

(define (get-var-words NUM)
  "Get the value grounded for a variable, in original words."
  (Get (State (chatlang-var-word NUM) (Variable "$x"))))

(define (get-var-lemmas NUM)
  "Get the value grounded for a variable, in lemmas."
  (Get (State (chatlang-var-lemma NUM) (Variable "$x"))))

(define (get-user-variable VAR)
  "Get the value of a user variable."
  (Get (State (Node VAR) (Variable "$x"))))

(define (assign-user-variable VAR VAL)
  "Assign a string value to a user variable."
  (Put (State (Node VAR) (Variable "$x"))
    ; Just to make sure there is no unneeded SetLink
    (if (equal? 'GetLink (cog-type VAL))
        VAL
        (Set VAL))))

(define (uvar-exist? VAR)
  "Check if a user variable has been defined in the atomspace."
  (Not (Equal (Set) (Get (State (Node VAR) (Variable "$x"))))))

(define (uvar-equal? VAR VAL)
  "Check if the value of the user variable VAR equals to VAL."
  (Equal (Set (WordNode VAL)) (Get (State (Node VAR) (Variable "$x")))))
