;;; esa.el --- Emacs integration for esa.io

;; Original Author: Masahiro Hayashi <mhayashi1120@gmail.com>
;; Original Created: 21 Jul 2008
;; Original URL: https://github.com/mhayashi1120/yagist.el
;; Author: Nab Inno <nab@blahfe.com>
;; Created: 21 May 2016
;; Version: 0.8.13
;; Keywords: tools esa
;; Package-Requires: ((cl-lib "0.3"))
;; URL: https://github.com/nabinno/esa.el

;; This file is NOT part of GNU Emacs.

;; This is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free
;; Software Foundation; either version 2, or (at your option) any later
;; version.
;;
;; This is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
;; for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
;; MA 02111-1307, USA.

;;; Commentary:

;; TODO:
;; - Encrypt risky configs

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'url)
(require 'derived)
(require 'easy-mmode)


;;; Configurations:

(defgroup esa nil
  "Simple esa application."
  :prefix "esa-"
  :group 'applications)
(defcustom esa-token nil
  "If non-nil, will be used as your Esa OAuth token."
  :group 'esa
  :type 'string)
(defcustom esa-team-name nil
  "If non-nil, will be used as your Esa team name."
  :group 'esa
  :type 'string)
(defcustom esa-view-esa nil
  "If non-nil, automatically use `browse-url' to view esas after they're
posted."
  :type 'boolean
  :group 'esa)
(defcustom esa-display-date-format "%Y-%m-%d %H:%M"
  "Date format displaying in `esa-list' buffer."
  :type 'string
  :group 'esa)
(defvar esa-authenticate-function nil
  "Authentication function symbol.")
(make-obsolete-variable 'esa-authenticate-function nil "0.8.13")
(defcustom esa-working-directory "~/.esa"
  "*Working directory where to go esa repository is."
  :type 'directory
  :group 'esa)
(defcustom esa-working-directory-alist nil
  "*Alist of esa numer as key, value is directory path.
.
Example:
\(setq esa-working-directory-alist
      `((\"1080701\" . \"~/myesa/Emacs-nativechecker\")))
"
  :type '(alist :key-type string
                :value-type directory)
  :group 'esa)


;;; Stores:

;; POST /v1/teams/%s/posts
;;;###autoload
(defun esa-region (begin end &optional wip)
  "Post the current region as a new paste at yourteam.esa.io
Copies the URL into the kill ring.
.
With a prefix argument, makes a wip paste."
  (interactive "r\nP")
  (let* ((name (read-from-minibuffer "Name: "))
         (category (read-from-minibuffer "Category: ")))
    (esa-request
     "POST"
     (format "https://api.esa.io/v1/teams/%s/posts" esa-team-name)
     'esa-created-callback
     `(("post" .
        (("name" . ,name)
         ("body_md" . ,(buffer-substring begin end))
         ("category" . ,category)
         ("wip" . ,(if wip 't :json-false))
         ))))))
(defun esa-single-file-name ()
  (let* ((file (or (buffer-file-name) (buffer-name)))
         (name (file-name-nondirectory file)))
    name))
(defun esa-anonymous-file-name ()
  (let* ((file (or (buffer-file-name) (buffer-name)))
         (name (file-name-nondirectory file))
         (ext (file-name-extension name)))
    (concat "anonymous-esa." ext)))
(defun esa-make-query-string (params)
  "Returns a query string constructed from PARAMS, which should be
a list with elements of the form (KEY . VALUE). KEY and VALUE
should both be strings."
  (let ((hexify
         (lambda (x)
           (url-hexify-string
            (with-output-to-string (princ x))))))
    (mapconcat
     (lambda (param)
       (concat (funcall hexify (car param))
               "="
               (funcall hexify (cdr param))))
     params "&")))
(defun esa-command-to-string (&rest args)
  (with-output-to-string
    (with-current-buffer standard-output
      (unless (= (apply 'call-process "git" nil t nil args) 0)
        (error "git command fails %s" (buffer-string))))))
;;;###autoload
(defun esa-region-wip (begin end)
  "Post the current region as a new wip paste at yourteam.esa.io
Copies the URL into the kill ring."
  (interactive "r")
  (esa-region begin end t))
;;;###autoload
(defun esa-buffer (&optional wip)
  "Post the current buffer as a new paste at yourteam.esa.io.
Copies the URL into the kill ring.
.
With a prefix argument, makes a wip paste."
  (interactive "P")
  (esa-region (point-min) (point-max) wip))
;;;###autoload
(defun esa-buffer-wip ()
  "Post the current buffer as a new wip paste at yourteam.esa.io.
Copies the URL into the kill ring."
  (interactive)
  (esa-region (point-min) (point-max) t))
;;;###autoload
(defun esa-region-or-buffer (&optional wip)
  "Post either the current region, or if mark is not set, the
current buffer as a new paste at yourteam.esa.io Copies the URL
into the kill ring.
.
With a prefix argument, makes a wip paste."
  (interactive "P")
  (if (esa-region-active-p)
      (esa-region (region-beginning) (region-end) wip)
    (esa-buffer wip)))
;;;###autoload
(defun esa-region-or-buffer-wip ()
  "Post either the current region, or if mark is not set, the
current buffer as a new wip paste at yourteam.esa.io Copies
the URL into the kill ring."
  (interactive)
  (if (esa-region-active-p)
      (esa-region (region-beginning) (region-end) t)
    (esa-buffer t)))
(defun esa-created-callback (status url json)
  (let ((json (save-excursion
                (goto-char (point-min))
                (when (re-search-forward "^\r?$" nil t)
                  (esa--read-json (point) (point-max)))))
        (http-url))
    (cond
     ((json-alist-p json)
      (setq http-url (cdr (assq 'url json)))
      (message "Paste created: %s" http-url)
      (when esa-view-esa
        (browse-url http-url)))
     (t
      (message (esa--err-propertize "failed"))))
    (when http-url
      (kill-new http-url))
    (url-mark-buffer-as-dead (current-buffer))))

;; GET /v1/teams/%s/posts
(defvar esa-list-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "g" 'revert-buffer)
    (define-key map "p" 'previous-line)
    (define-key map "n" 'forward-line)
    (define-key map "q" 'esa-quit-window)
    map))
(define-derived-mode esa-list-mode fundamental-mode "Esa"
  "Show your esa list"
  (setq buffer-read-only t)
  (setq truncate-lines t)
  (set (make-local-variable 'revert-buffer-function)
       'esa-list-revert-buffer)
  (use-local-map esa-list-mode-map))
;;;###autoload
(defun esa-list ()
  "Displays a list of all of the current user's esas in a new buffer."
  (interactive)
  (message "Retrieving list of your esas...")
  (esa-list-draw-esas))
(defun esa-quit-window (&optional kill-buffer)
  "Bury the *esas* buffer and delete its window.
With a prefix argument, kill the buffer instead."
  (interactive "P")
  (quit-window kill-buffer))
(defun esa-list-draw-esas (&optional q)
  (with-current-buffer (get-buffer-create "*esas*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (esa-list-mode)
      (esa-insert-list-header))
    ;; suppress multiple retrieving
    (setq esa-list--paging-info t))
  (esa-request
   "GET"
   (format "https://api.esa.io/v1/teams/%s/posts" esa-team-name)
   'esa-lists-retrieved-callback
   (if q `(("q" . ,q)))))
(defun esa-list-revert-buffer (&rest ignore)
  ;; redraw esa list
  (esa-list))
(defun esa-region-active-p ()
  (if (functionp 'region-active-p)
      ;; trick for suppressing elint warning
      (funcall 'region-active-p)
    (and transient-mark-mode mark-active)))
(defun esa-lists-retrieved-callback (status url params)
  "Called when the list of esas has been retrieved. Parses the result
and displays the list."
  (goto-char (point-min))
  (when (re-search-forward "^\r?$" nil t)
    (let* ((json (append
                  (cdr (assq 'posts (esa--read-json (point) (point-max))))
                  nil)))
      (with-current-buffer (get-buffer-create "*esas*")
        (save-excursion
          (let ((inhibit-read-only t))
            (goto-char (point-max))
            (mapc 'esa-insert-esa-link json)))
        ;; skip header
        (forward-line)
        (set-window-buffer nil (current-buffer)))))
  (url-mark-buffer-as-dead (current-buffer)))

;; DELETE /v1/teams/%s/posts/%s
(defun esa-delete (number)
  (esa-request
   "DELETE"
   (format "https://api.esa.io/v1/teams/%s/posts/%s" esa-team-name number)
   (esa-simple-receiver "Delete")))

;; PATCH /v1/teams/%s/posts/%s
(defun esa-update-body-md (number body_md)
  (esa-request
   "PATCH"
   (format "https://api.esa.io/v1/teams/%s/posts/%s" esa-team-name number)
   (esa-simple-receiver "Update body.md")
   `(,@(and body_md
            `(("body_md" . ,body_md))))))
(defun esa-update-name (number name)
  (esa-request
   "PATCH"
   (format "https://api.esa.io/v1/teams/%s/posts/%s" esa-team-name number)
   (esa-simple-receiver "Update name")
   `(,@(and name
            `(("name" . ,name))))))
(defun esa-update-category (number category)
  (esa-request
   "PATCH"
   (format "https://api.esa.io/v1/teams/%s/posts/%s" esa-team-category number)
   (esa-simple-receiver "Update category")
   `(,@(and category
            `(("category" . ,category))))))


;;; Components:

;; esa entries list (esas)
(defun esa-insert-list-header ()
  "Creates the header line in the esa list buffer."
  (save-excursion
    (insert "  No   Updated           Prog   Full Name               "
            (esa-fill-string "" (frame-width))
            "\n"))
  (let ((ov (make-overlay (line-beginning-position) (line-end-position))))
    (overlay-put ov 'face 'header-line))
  (forward-line))
(defun esa-insert-esa-link (esa)
  "Inserts a button that will open the given esa when pressed."
  (let* ((data (esa-parse-esa esa))
         (number (cdr (assq 'number data))))
    (dolist (x (cdr data))
      (insert (format "  %s" x)))
    (make-text-button (line-beginning-position) (line-end-position)
                      'repo number
                      'action 'esa-describe-button
                      'face 'default
                      'esa-json esa))
  (insert "\n"))
(defun esa-parse-esa (esa)
  "Returns a list of the esa's attributes for display, given the xml list
for the esa."
  (let ((number (cdr (assq 'number esa)))
        (updated-at (cdr (assq 'updated_at esa)))
        (full_name (cdr (assq 'full_name esa)))
        (progress (if (eq (cdr (assq 'wip esa)) 't)
                      "WIP"
                    "Ship")))
    (list number
          (esa-fill-string (number-to-string number) 3)
          (esa-fill-string
           (format-time-string
            esa-display-date-format (esa-parse-time-string updated-at))
           16)
          (esa-fill-string progress 5)
          (or full_name ""))))
(defun esa-parse-time-string (string)
  (let* ((times (split-string string "[-T:Z]" t))
         (getter (lambda (x) (string-to-number (nth x times))))
         (year (funcall getter 0))
         (month (funcall getter 1))
         (day (funcall getter 2))
         (hour (funcall getter 3))
         (min (funcall getter 4))
         (sec (funcall getter 5)))
    (encode-time sec min hour day month year 0)))
(defun esa-fill-string (string width)
  (truncate-string-to-width string width nil ?\s "..."))

;; esa entry (esa)
(defun esa-describe-button (button)
  (let ((json (button-get button 'esa-json)))
    (with-help-window "*esa*"
      (with-current-buffer standard-output
        (esa-describe-esa-1 json)))))
(defun esa-describe-insert-button (text action json)
  (let ((button-text text)
        (button-face (if (display-graphic-p)
                         '(:box (:line-width 2 :color "dark grey")
                                :background "light grey"
                                :foreground "black")
                       'link))
        (number (cdr (assq 'number json))))
    (insert-text-button button-text
                        'face 'default
                        'follow-link t
                        'action action
                        'repo number
                        'esa-json json)
    (insert " ")))
(defun esa-describe-esa-1 (esa)
  (require 'lisp-mnt)
  (let ((number (cdr (assq 'number esa)))
        (name (cdr (assq 'name esa)))
        (category (cdr (assq 'category esa)))
        (progress (eq (cdr (assq 'wip esa)) nil))
        (updated (cdr (assq 'updated_at esa)))
        (url (cdr (assq 'url esa)))
        (body_md (cdr (assq 'body_md esa))))
    (insert "    ") (esa-describe-insert-button "Name:" 'esa-update-name-button esa) (insert (or name "") "\n")
    (insert "") (esa-describe-insert-button "Category:" 'esa-update-category-button esa) (insert (or category "") "\n")
    (insert "Progress:"
     (if progress
         (propertize " Ship" 'font-lock-face `(bold ,font-lock-warning-face))
       (propertize " WIP" 'font-lock-face '(bold)))
     "\n")
    (insert " " (propertize "Updated: " 'font-lock-face 'bold)
            (format-time-string
             esa-display-date-format
             (esa-parse-time-string updated)) "\n")
    (insert "     " (propertize "URL: " 'font-lock-face 'bold)) (esa-describe-insert-button url 'esa-open-web-button esa) (insert "\n")
    (insert "-\n\n")
    (insert (or body_md "") "\n")
    (insert "\n\n")
    (esa-describe-insert-button "[Edit]" 'esa-update-body-md-button esa)
    (esa-describe-insert-button "[Delete]" 'esa-delete-button esa)))
(defun esa-delete-button (button)
  "Called when a esa [Delete] button has been pressed.
Confirm and delete the esa."
  (when (y-or-n-p "Really delete this esa entry? ")
    (esa-delete (button-get button 'repo))))
(defun esa-update-body-md-button (button)
  "Called when a esa [Edit] button has been pressed.
Edit the esa body_md."
  (let* ((json (button-get button 'esa-json))
         (body_md (read-from-minibuffer
                "Body.md: "
                (cdr (assq 'body_md json)))))
    (esa-update-body-md (button-get button 'repo) body_md)))
(defun esa-update-name-button (button)
  "Called when a esa [Edit] button has been pressed.
Edit the esa name."
  (let* ((json (button-get button 'esa-json))
         (name (read-from-minibuffer
                "Name: "
                (cdr (assq 'name json)))))
    (esa-update-name (button-get button 'repo) name)))
(defun esa-update-category-button (button)
  "Called when a esa [Edit] button has been pressed.
Edit the esa category."
  (let* ((json (button-get button 'esa-json))
         (category (read-from-minibuffer
                "Category: "
                (cdr (assq 'category json)))))
    (esa-update-category (button-get button 'repo) category)))
(defun esa-open-web-button (button)
  "Called when a esa [Browse] button has been pressed."
  (let* ((json (button-get button 'esa-json))
         (url (cdr (assq 'url json))))
    (browse-url url)))


;;; Utilities:

;; rest client
(defun esa--read-json (start end)
  (let* ((str (buffer-substring start end))
         (decoded (decode-coding-string str 'utf-8)))
    (json-read-from-string decoded)))
(defun esa-request-0 (auth method url callback &optional json-or-params)
  (let* ((json (and (member method '("POST" "PATCH")) json-or-params))
         (params (and (member method '("GET" "DELETE")) json-or-params))
         (url-request-data (and json (concat (json-encode json) "\n")))
         (url-request-extra-headers
          `(("Authorization" . ,auth)
            ("Content-Type" . "application/json;charset=UTF-8")))
         (url-request-method method)
         (url-max-redirection -1)
         (url (if params
                  (concat url "?" (esa-make-query-string params))
                url)))
    (url-retrieve url callback (list url json-or-params))))
(defun esa-request (method url callback &optional json-or-params)
  (let ((token (esa-check-oauth-token)))
    (esa-request-0
     (format "Bearer %s" token)
     method url callback json-or-params)))
(defun esa-check-oauth-token ()
  (cond
   (esa-token)
   (t
    (browse-url (format "https://%s.esa.io/user/token" esa-team-name))
    (error "You need to get OAuth Access Token by your browser"))))

;; callback
(defun esa-simple-receiver (message)
  ;; Create a receiver of `esa-request-0'
  `(lambda (status url json-or-params)
     (goto-char (point-min))
     (when (re-search-forward "^HTTP/1.1 \\([0-9]+\\)" nil t)
       (let ((code (string-to-number (match-string 1))))
         (if (and (<= 200 code) (< code 300))
             (progn (switch-to-buffer "*esa*")
                    (kill-buffer-and-window)
                    (esa-list)
                    (message "%s succeeded" ,message))
           (message "%s %s"
                    code
                    ;; ,message
                    (esa--err-propertize "failed")))))
     (url-mark-buffer-as-dead (current-buffer))))

;; exception handling
(defun esa--err-propertize (string)
  (propertize string 'face 'font-lock-warning-face))



(provide 'esa)
;;; esa.el ends here
