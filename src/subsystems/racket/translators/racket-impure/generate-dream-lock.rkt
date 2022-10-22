#lang racket/base

(require json)
(require racket/file)
(require racket/match)
(require racket/list)
(require racket/set)
(require racket/string)
(require setup/getinfo)

(provide generate-dream-lock)

;; XXX: We presently end up doing multiple DFSes in the course of
;; generating multiple dream-lock.json files for foo, foo-lib,
;; foo-test: the issue is that generating the foo dream-lock requires
;; that we traverse foo-lib, and that subsequently generating the
;; foo-lib dream-lock requires repeating the same traversal of foo-lib. How can this be avoided?

(define (generate-dream-lock pkgs-all-path)
  (letrec ([src-path (getenv "RACKET_SOURCE")]
           [rel-path (getenv "RACKET_RELPATH")]
           [package-path (simplify-path (cleanse-path (build-path src-path (if (string=? rel-path "")
                                                                               'same
                                                                               rel-path))))]
           [parent-path (simplify-path (cleanse-path (build-path package-path 'up)))]
           [package-name (if (string=? rel-path "")
                             (getenv "RACKET_PKG_MAYBE_NAME")
                             (path->string
                              (match/values (split-path package-path)
                                ((_base subdir _must-be-dir?) subdir))))]
           [pkgs-all (with-input-from-file pkgs-all-path read)]
           [pkg-in-stdlib? (lambda (pkg-name)
                             (or ;; Some people add racket itself as a dependency for some reason
                              (string=? pkg-name "racket")
                              (ormap (lambda (tag)
                                       ;; XXX: would prefer to use memq, but tag is mutable for some reason
                                       (member tag  '("main-distribution" "main-tests")))
                                     (hash-ref (hash-ref pkgs-all pkg-name) 'tags))))]
           [dep-alist-from-catalog (hash-map pkgs-all
                                             (match-lambda**
                                              [(name (hash-table ('dependencies dependencies)))
                                               (let ([external-deps (filter-not pkg-in-stdlib? dependencies)])
                                                 (cons name external-deps))]))]
           [compute-overridden-dep-lists
            (lambda (name dir)
              (let ([info-procedure (get-info/full dir)])
                (and info-procedure
                     (cons name
                           (remove-duplicates
                            (filter-not pkg-in-stdlib?
                                        (map (match-lambda
                                               [(or (cons pkg-name _) pkg-name)
                                                pkg-name])
                                             (append (with-handlers ([exn:fail? (lambda (_) '())])
                                                       (info-procedure 'deps))
                                                     (with-handlers ([exn:fail? (lambda (_) '())])
                                                       (info-procedure 'build-deps))))))))))]
           [dep-list-overrides
            ;; XXX: this probably doesn't capture every case since
            ;; Racket doesn't seem to enforce much structure in a
            ;; multi-package repo, but it accounts for the only cases
            ;; that a sane person would choose
            (if (string=? rel-path "")
                (list (compute-overridden-dep-lists package-name package-path))
                (let* ([sibling-paths (filter directory-exists?
                                              (directory-list parent-path #:build? #t))]
                       [names-of-sibling-paths (map (lambda (p)
                                                      ;; XXX: maybe not very DRY
                                                      (path->string
                                                       (match/values (split-path p)
                                                         ((_base dir-fragment _must-be-dir?) dir-fragment))))
                                                    sibling-paths)])
                  (filter-map compute-overridden-dep-lists
                              names-of-sibling-paths
                              sibling-paths)))]
           [names-of-overridden-packages (apply set (map car dep-list-overrides))]
           [graph (make-immutable-hash (append dep-alist-from-catalog
                                               dep-list-overrides))]
           ;; TODO: no effort is made to handle cycles right now
           [dfs (lambda (u dependency-subgraph)
                  (if (hash-has-key? dependency-subgraph u)
                      dependency-subgraph
                      (let ([destinations (hash-ref graph u)])
                        (foldl dfs
                               (hash-set dependency-subgraph u destinations)
                               destinations))))]
           [dependency-subgraph (dfs package-name (make-immutable-hash))]
           [generic (make-immutable-hash
                     `((subsystem . "racket")
                       (location . ,rel-path)
                       (sourcesAggregatedHash . ,(json-null))
                       (defaultPackage . ,package-name)
                       (packages . ,(make-immutable-hash `((,(string->symbol package-name) . "0.0.0"))))))]
           [sources-from-catalog
            (hash-map pkgs-all
                      (match-lambda**
                       [(name (hash-table
                               ('versions
                                (hash-table
                                 ('default
                                  (hash-table
                                   ('source_url url)))))
                               ('checksum rev)))
                        (let* ([source-with-removed-http-or-git-double-slash (regexp-replace #rx"^(?:git|http)://" url "https://")]
                               [left-trimmed-source (string-trim source-with-removed-http-or-git-double-slash "git+" #:right? #f)]
                               [maybe-match-path (regexp-match #rx"\\?path=([^#]+)" left-trimmed-source)]
                               [trimmed-source (regexp-replace #rx"(?:/tree/.+)?(?:\\?path=.+)?$" left-trimmed-source "")])
                          (cons (string->symbol name)
                                (make-immutable-hash
                                 `((0.0.0 . ,(make-immutable-hash
                                              (append (match maybe-match-path
                                                        [(list _match dir)
                                                         `((dir . ,(regexp-replace* #rx"%2F" dir "/")))]
                                                        [_ '()])
                                               `((url . ,trimmed-source)
                                                 (rev . ,rev)
                                                 (type . "git")
                                                 ;; TODO: sha256?
                                                 ))))))))]))]
           [sources-from-repo (if (string=? rel-path "")
                                  (list (cons (string->symbol package-name)
                                              (make-immutable-hash
                                               `((0.0.0 . ,(make-immutable-hash
                                                            `((type . "path")
                                                              (path . ,src-path))))))))
                                  (set-map names-of-overridden-packages
                                           (lambda (name)
                                             (cons (string->symbol name)
                                                   (make-immutable-hash
                                                    `((0.0.0 . ,(make-immutable-hash
                                                                 `((type . "path")
                                                                   (path . ,(path->string (build-path parent-path (string-append-immutable name "/")))))))))))))]
           [sources-hash-table (make-immutable-hash (append sources-from-catalog
                                                            sources-from-repo))]
           [sources (make-immutable-hash (hash-map dependency-subgraph
                                                   (lambda (name _v)
                                                     (cons (string->symbol name) (hash-ref sources-hash-table (string->symbol name))))))]
           [dream-lock (make-immutable-hash
                        `((_generic . ,generic)
                          (sources . ,sources)
                          (_subsystem . ,(make-immutable-hash))
                          (dependencies . ,(make-immutable-hash
                                            (hash-map dependency-subgraph
                                                      (lambda (name dep-list)
                                                        (cons (string->symbol name)
                                                              (make-immutable-hash `((0.0.0 . ,(map (lambda (dep-name) (list dep-name "0.0.0")) dep-list)))))))))))])
    (make-parent-directory* (getenv "RACKET_OUTPUT_FILE"))
    (with-output-to-file (getenv "RACKET_OUTPUT_FILE")
      (lambda () (write-json dream-lock))
      #:exists 'replace)))
