;;; cesp.el --- Live-share client for Emacs         -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Wisdurm

;; Author: Wisdurm <luukas.kola@gmail.com>
;; Keywords: comm, files

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Cesp is a protocol for facilitating cross-platform live file
;; editing. This package implements the protocol in Emacs.

;;; Code:

(require 'cesp-browse-mode)

;;; Public variables

(defgroup cespconf nil
  "Variables related to configuring Cesp."
  :group 'communication)

(defcustom cesp-name "Jaakko"
  "Your username on Cesp.
This is the name other users will see when
you are editing with them"
  :group 'cespconf
  :type 'string)

;;; Internal variables

(defvar cesp-is-host
  nil
  "Am I the host?")

(defvar cesp-server-process
  nil
  "The internal server process object.
This is the process object that represents
the connection to the tcp server")

(defvar cesp-cursors
  nil
  "An alist of other peoples cursors.
Cursors are overlays.
These will be shown, if you are in the
corresponding buffer.

Format is:
  (id . overlay )")

(defvar cesp--old-last
  nil
  "Stores a line value before edits are made.")

(defvar cesp--messafe-buffer
  nil
  "Stores unparsed data received from the server.")

(make-variable-buffer-local
 (defvar cesp--initialized nil
   "Whether or not initial content has been added."))

(make-variable-buffer-local
 (defvar cesp--last-position 0
   "Holds the cursor position from the last run of post-command-hooks."))

;;; Public commands

;;;; Connection management

;;;###autoload
(defun cesp-connect-server(host port owner)
  "Connects to a Cesp server.
This connects your Emacs session to a Cesp server
at HOST PORT, for example localhost 8080
which is the default for a Cesp server.
OWNER specifies whether or not you wish to become
the host, if possible.

It will then perform the handshake, giving your
name as per the variable"
  (interactive
   (list (read-string "Server hostname: ")
		 (read-string "Server port: ")
		 (y-or-n-p "Become host if possible? ")))
  (if (not (cesp-connected-p))
	  (progn
		(setq cesp-server-process (make-network-process
								   :name "cesp-process"
								   :buffer (get-buffer-create "*cesp*") ;; Don't think this does anything
								   :host host
								   :service port
								   :family #'ipv4 ;; TODO: Support for ipv6
								   :filter #'cesp--filter
								   :sentinel #'cesp--sentinel))
		;; Perform handshake
		(cesp--send `((event . "handshake") (name . ,cesp-name) (host . ,(or owner
																			 :false)))))
	(error "You are already connected to a server!")))

;;;###autoload
(defun cesp-disconnect()
  "Disconnects Emacs from the Cesp server.
This will disconnect the Emacs from
the Cesp server it is currently connected to, if
any"
  (interactive)
  (if (cesp-connected-p)
	  (delete-process "cesp-process")
	(error "You are not connected to a server!")))

;;;; File handling

;;;###autoload
(defun list-cesp-files()
  "Sends a request to get the host's files.
This will send a request_files event to the host.
This function does not handle the response"
  (interactive)
  (if (cesp-connected-p)
	  (cesp--send '((event . "request_files")))
	(error "You are not connected to a server!")))

;;;###autoload
(defun cesp-get-file(file)
  "Sends a request to get FILE from the host's computer.

This function may be used directly, or by cesp-browse-mode"
  (interactive "sFile path: ")
  (if (cesp-connected-p)
	  (cesp--send `((event . "request_file") (path . ,file)))
	(error "You are not connected to a server!")))

;;;###autoload
(defun cesp-reload-buffer()
  "Reloads the file in the current buffer."
  (interactive)
  (if cesp-mode
	  (cesp-get-file (buffer-name))
	(error "You are not in a Cesp buffer!")))

;;;; Other

;;;###autoload
(defun cesp-connected-p()
  "Is a Cesp connection currently active?"
  (interactive)
  (if (and cesp-server-process (process-live-p cesp-server-process))
	  t
	nil))

;;;###autoload
(define-minor-mode cesp-mode
  "Toggles local cesp-mode."
  :init-value nil
  :lighter " Cesp:Shared"
  :interactive nil
  (if cesp-mode
	  (progn
		(add-hook 'before-change-functions #'cesp--handle-before nil t)
		(add-hook 'after-change-functions #'cesp--send-update nil t)
		(add-hook 'post-command-hook #'cesp--send-mouse nil t))
	(progn
	  (remove-hook 'before-change-functions #'cesp--handle-before t)
	  (remove-hook 'after-change-functions #'cesp--send-update t)
	  (remove-hook 'post-command-hook #'cesp--send-mouse nil t))))

;;; Internal functions

(defun cesp--send(json-object)
  "Sends the server a message formatted in Json.
This sends JSON-OBJECT to the Cesp server, which will then
forward the message accordingly to other clients or
the host.

JSON is an object that is parsed by `json-serialize'
into a string."
  (process-send-string cesp-server-process (concat (json-serialize json-object) "\n")))

(defun cesp--get-files(dir)
  "Return a list containing file names starting from DIR."
  (let ((file-list nil))
	(dolist (entry (directory-files-and-attributes dir) nil)
	  ;; Straight up ignore all hidden files, for now
	  (if (not (equal (aref (car entry) 0) ?.))
		  ;; If directory, recurse
		  ;; (also make sure not to recurse . or .. :D )
		  (if (and (car (cdr entry))
				   (not (equal (car entry) "."))
				   (not (equal (car entry) "..")))
			  (setq file-list (append file-list (cesp--get-files (concat dir "/" (car entry)) )))
			;; Otherwise, add to list
			(setq file-list (cons (concat dir "/" (car entry)) file-list)))))
	file-list))

(defun cesp--handle-before(beg end)
  "Handle things that happen before edits are made.
Handler function with BEG and END."
  (setq cesp--old-last (line-number-at-pos end t)))

(defun cesp--send-update(beg end len)
  "Sends an update_content event after a buffer is updated.
This sends content between BEG and END to the server, LEN is unused."
  (if cesp--initialized
	  (let* ((first (1- (line-number-at-pos beg t)))
			 (new-last (line-number-at-pos end t))
 			 (nline "
")
			 ;; Lines after update
			 (lines (split-string (cesp--get-lines first new-last) nline nil)))
		;(message "Beg: %i End: %i Len: %i First: %i Old-last: %i New-last: %i Line: %s" beg end len first cesp--old-last new-last (car lines)))))
		(cesp--send `((event . "update_content") (path . ,(buffer-name))
		 			  (changes . ((first . ,first) (old_last . ,cesp--old-last) (lines . ,(vconcat lines)))) )))))

(defun cesp--get-lines(start last)
  "Get lines from START to LAST.
START is inclusive, LAST is exclusive."
  (save-restriction
	(widen)
	(let* ((beg (save-excursion
				  (goto-char (point-min))
				  (forward-line start)
				  (point)))
		   (end (max beg (save-excursion
						   (goto-char (point-min))
						   (forward-line last)
						   ;; 1- is for newline fix but if at end of file
						   ;; it is not needed
						   (if (= (point) (point-max))
							   (point)
							 (1- (point)))))))
	  (buffer-substring-no-properties beg end))))

(defun cesp--send-mouse()
  "Send the current mouse position to the server."
  (unless (equal (point) cesp--last-position)
	(let* ((col (1- (line-number-at-pos (point) t)))
		   (ln-begin (save-excursion
					   (beginning-of-line)
					   (point)))
		   (row (- (point) ln-begin))
		   (pos `(,col ,row)))
	  (cesp--send `((event . "cursor_move") (position . ,(vconcat pos)) (path . ,(buffer-name))))))
  (setq cesp--last-position (point)))

(defun cesp--save-file(&optional ARG)
  "If Cesp buffer send save event
ARG is unused."
  (if cesp-mode
	  (progn
		(message "(Sent remote_write event)")
		(cesp--send `((event . "remote_write") (path . ,(buffer-name))))
		t)
	nil))

;;;; Handlers

(defun cesp--filter(proc msg)
  "Main function which will parse Cesp input from MSG.
This function receives all of the data received
by the tcp connection, and calls other functions,
as appropriate. PROC is unused."
  ;; Store data in buffer because it doesn't always
  ;; come in one packet
  (push msg cesp--messafe-buffer)
  (if (string-search "
" msg)
	  (let* ((nline "
")
			 (raw-data (mapconcat #'identity (reverse cesp--messafe-buffer)))
			 (lines (split-string raw-data nline nil))
			 (leftover (last lines)))
		(setq lines (butlast lines))
		(setq cesp--messafe-buffer leftover)
		;; Handle lines
		(dolist (string lines)
		  ;;(message "MESSAGE: %s" raw-data)
		  ;; Event handling
		  (let* ((json (json-parse-string string
										  :object-type 'alist
										  :array-type 'list))
				 (event (cdr (assoc 'event json))))
			;;(message (concat "Event is: " event))
			(cond
			 ((string= "response_files" event)
			  ;;(cesp--open-file-manager (cdr (assoc 'files json)) )
			  (cesp--open-file-menu (cdr (assoc 'files json))))
			 ((string= "response_file" event)
			  (cesp--open-remote-file
			   (cdr (assoc 'path json))
			   (cdr (assoc 'content json))))
			 ((string= "update_content" event)
			  (cesp--update-content
			   (cdr (assoc 'path json))
			   (cdr (assoc 'changes json))))
			 ((string= "cursor_move" event)
			  (cesp--render-cursor
			   (cdr (assoc 'from_id json))
			   (cdr (assoc 'position json))
			   (cdr (assoc 'path json))
			   (cdr (assoc 'name json))))
			 ((string= "handshake_response" event)
			  (cesp--connected json))))))))

(defun cesp--sentinel(proc msg)
  "Sentinel function which will handle status change in connection.
PROC and MSG are used somehow, idk."
  (if (string= msg "connection broken by remote peer\n")
      (message (format "client %s has quit" proc))
	(message (concat "SENTINEL MESSAGE: "  msg))))

(defun cesp--connected(json)
  "Function called when handshake_response is received.
JSON is the json message directly received from the server"
  (message "Connected to Cesp!")
  (or (and (cdr (assoc 'is_host json))
		   (setq cesp-is-host t))
	  (setq cesp-is-host nil)))

(defun cesp--open-file-menu(files)
  "Handler function which opens a menu to pick FILES."
  (cesp-get-file (completing-read
				  "Pick a file to open: "
				  files nil t)))

(defun cesp--open-file-manager(files)
  "Handler function which opens a Cesp file browser.
This will open a new window in cesp-browse-mode, where you
can browse files on the host's computer, and open them in
new buffers

FILES should be a list of file paths (strings)."
  (let ((file-window  (split-window-horizontally)))
	(set-window-buffer file-window (get-buffer "*scratch*"))
	(save-window-excursion ;; Set major mode
	  (select-window file-window)
	  (cesp-browse-mode)
	  ;; Convert file list into tabulated data
	  (setq tabulated-list-entries nil)
	  (dolist (file files nil)
		(setq tabulated-list-entries (cons (list
											nil (vector "Jaakko Pekka" file)
											)
										   tabulated-list-entries)))
	  (tabulated-list-print) ;; This doesn't seem very appropriate...
	  ;; I'm not sure where else to do this though, since it's
	  ;; hard to pass the data to the major mode startup
	  )))

(defun cesp--open-remote-file(path content)
  "Handler functon which opens a buffer with CONTENT.
This will create a buffer with the Cesp minor mode
instantiated, which means the buffers contents are
synchronized across the Cesp server.
PATH will be the the name of the new buffer.

If the buffer already exists, this will refresh the
contents."
  (switch-to-buffer (get-buffer-create path))
  (setq-local cesp--initialized nil)
  ;; Replace everything
  (widen)
  (kill-region (point-min) (point-max))
  (insert content)
  ;; Try to activate appropriate major and minor modes.
  ;; This could definitely be better
  (funcall (cdr (assoc (buffer-name) auto-mode-alist 'string-match-p)))
  ;; Initiate cesp-mode
  (cesp-mode 1)
  (setq-local cesp--initialized t))

;; (defun cesp--lie-about-file-name(file)
;;   "Function which intercepts `buffer-file-name' to lie.
;; If `buffer-file-name' returns a real buffer name, everything
;; works normally. However, if it is nil, and the buffer is marked
;; as an Cesp buffer, this will instead return the `buffer-name'.
;; This effectively lies to Emacs in order to get it to activate
;; the correct modes automatically"
;;   (or file
;; 	  (buffer-name)))
;; (advice-add 'buffer-file-name :filter-return #'cesp--lie-about-file-name)
;; (advice-remove 'buffer-file-name #'cesp--lie-about-file-name)

(defun cesp--render-cursor(id position buffer name)
  "Renders cursor ID at POSITION in BUFFER.
ID is unique id for cursor, POSITION is a list
with a column and row. NAME is rendered next to the
cursor.
The cursor is not rendered if you are not in the correct
buffer."
  (let ((buf (get-buffer buffer)))
	(if buf
		(let* ((pos (save-excursion ;; Get pos from column and row
					  (save-restriction
						(widen)
						(set-buffer buffer)
						(goto-char (point-min))
						(forward-line (car position))
						(forward-char (car (cdr position)))
						(point))))
					(overlay (or (cdr (assoc id cesp-cursors))
								 (let ((o (make-overlay pos (1+ pos) buf)))
								   (overlay-put o 'face 'cursor)
								   (setq cesp-cursors (cons `(,id . ,o) cesp-cursors))
								   o))))
			   ;; Update values
			   (move-overlay overlay pos (1+ pos) buf)))))

(defun cesp--update-content(path changes)
  "Handler function which will apply change to buffer PATH.
If the specified buffer is not currently open, then
the changes are not applied.

CHANGES is an alist with the changes specified as such:
- first: First line (with 0 as the first line)
- old_last: Last line I guess?
- lines: List of the lines as they are now"
  (let ((buffer (get-buffer path)))
	(if buffer
		(save-excursion ;; THIS ENTIRE BLOCK IS SUBJECT TO OPTIMIZATION
		  (set-buffer buffer)
		  (save-restriction
			(widen)
		  (let ((beg (cdr (assoc 'first changes)) )
				(end (cdr (assoc 'old_last changes)) )
				(lines (cdr (assoc 'lines changes)) ))
			;; Goto first line
			(goto-char (point-min))
			(forward-line beg)
			;; Replace lines iteratively
			;; (also make sure this doesn't trigger the cesp after-change hook)
			(setq inhibit-modification-hooks t)
			(dotimes (_ (- end beg))
			  (delete-line))
			(dolist (line lines)
			  (insert (concat line "\n")))
			(setq inhibit-modification-hooks nil)))))))

;;; _
(advice-add 'save-buffer :before-until #'cesp--save-file)
										;(advice-remove 'save-buffer #'cesp--save-file)
(provide 'cesp)
;;; cesp.el ends here
