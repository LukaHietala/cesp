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

;;; Public variables

(defgroup cesp nil
  "Variables related to configuring Cesp."
  :group 'communication)

(defcustom cesp-name "Jaakko"
  "Your username on Cesp.
This is the name other users will see when
you are editing with them"
  :group 'cespconf
  :type 'string)

;;; Internal variables

(defvar cesp-server-process
  nil
  "The internal server process object.
This is the process object that represents
the connection to the tcp server")

(defvar cesp-cursors
  nil
  "An alist of other peoples cursors.
There are two overlays, one for the cursor
itself and another for the name.
These will be shown, if you are in the
corresponding buffer.

Format is:
  (id . (cursor-overlay name-overlay) )")

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
(defun cesp-connect-server(host port)
  "Connects to a Cesp server.
This connects your Emacs session to a Cesp server
at HOST PORT, for example localhost 8080
which is the default for a Cesp server.

It will then perform the handshake, giving your
name as per the variable"
  (interactive
   (list (read-string "Server hostname: ")
		 (read-string "Server port: ")))
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
		(cesp--send "auth:handshake" `((name . ,cesp-name))))
	(error "You are already connected to a server!")))

;;;###autoload
(defun cesp-disconnect()
  "Disconnects Emacs from the Cesp server.
This will disconnect the Emacs from
the Cesp server it is currently connected to, if
any"
  (interactive)
  (if (cesp-connected-p)
	  (progn
		(delete-process "cesp-process")
		(cesp--clear-cursors)
		(message "Disconnected from Cesp server"))
	(error "You are not connected to a server!")))

;;;; File handling

;;;###autoload
(defun list-cesp-files()
  "Sends a request to get the host's files.
This will send a request_files event to the host.
This function does not handle the response"
  (interactive)
  (if (cesp-connected-p)
	  (cesp--send "fs:list" nil)
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

(defun cesp--send(event payload)
  "Sends the server a message formatted in Json.
This sends EVENT and PAYLOAD to the Cesp server, which
will then forward the message accordingly to other clients
or the host.

PAYLOAD is an object that is parsed by `json-serialize'
into a string."
  (let ((msg (json-serialize `((event . ,event) (payload . ,payload)))))
	(process-send-string cesp-server-process
					   (concat
						'(#x0C ;; Magic 1
						  #x0E) ;; Magic 2
						(cesp--to-uint32 (length msg)) ;; Length
						msg))))

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
		(cesp--send "doc:update"
					`((path . ,(buffer-name))
		 			  (range . ,(vconcat `(,first ,cesp--old-last)))
					  (lines . ,(vconcat lines)))))))

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
	(if (region-active-p)
		(cesp--send "cursor:range"
					`((range . ,(vconcat (cesp--col-and-row (point))
											(cesp--col-and-row (mark))))
					  (path . ,(buffer-name))))
	  ;; If not highlighting
	  (cesp--send "cursor:move"
				  `((pos . ,(vconcat (cesp--col-and-row (point))))
					(path . ,(buffer-name))))))
  (setq cesp--last-position (point)))

(defun cesp--col-and-row(point)
  "Gets the column and row numbers of POINT.
Returns a list with a column and row number.
Column is 0-indexed."
  (let* ((col (1- (line-number-at-pos point t)))
		 (ln-begin (save-excursion
					 (save-restriction
					   (widen)
					   (goto-char (point-min))
					   (forward-line col)
					   (beginning-of-line)
					   (point))))
		 (row (- point ln-begin))
		 (pos `(,col ,row)))
	pos))

(defun cesp--point-from-pos(col row)
  "Returns point from COL and ROW.
COL is 0-indexed."
  (save-excursion
	(save-restriction
	  (widen)
	  (goto-char (point-min))
	  (forward-line col)
	  (forward-char row)
	  (point))))

(defun cesp--save-file(&optional ARG)
  "If Cesp buffer send save event.
ARG is unused."
  (if cesp-mode
	  (progn
		(message "(Sent doc:write event)")
		(cesp--send "doc:write" `((path . ,(buffer-name))))
		t)
	nil))

(defun cesp-get-file(file)
  "Sends a request to get FILE from the host's computer."
  (cesp--send "doc:open"  `((path . ,file))))

;;;; Handlers

(defun cesp--filter(proc msg)
  "Main function which will parse Cesp input from MSG.
This function receives all of the data received
by the tcp connection, and calls other functions,
as appropriate. PROC is unused."
  ;; Store data in buffer because it doesn't always
  ;; come in one packet
  (push msg cesp--messafe-buffer)
  (let* ((raw-data (mapconcat #'identity (reverse cesp--messafe-buffer)))
		 (lines (cesp--split-magic raw-data))
		 (leftover (last lines)))
	(setq lines (butlast lines))
	(setq cesp--messafe-buffer leftover)
	;; Handle lines
	(dolist (string lines)
	  ;;(message "Message: %s" string)
	  ;; Event handling
	  (let* ((json (json-parse-string string
									  :object-type 'alist
									  :array-type 'list))
			 (event (cdr (assoc 'event json)))
			 (payload (cdr (assoc 'payload json))))
		(pcase payload
		  ;; Ping
		  ((guard (string= "ping" event))
		   (cesp--send "pong" nil))
		  ;; Server
		  ((and (guard (string= "server:error" event))
				(map message))
		   (message "Cesp server: %s" message))
		  ;; Authentication
		  ((guard (string= "auth:handshake_res" event))
		   (message "Connected to Cesp!"))
		  ;; File system
		  ((and (guard (string= "fs:list_res" event))
				(map files))
		   (cesp--open-file-menu files))
		  ;; Document
		  ((and (guard (string= "doc:open_res" event))
				(map path content))
		   (cesp--open-remote-file path content))
		  ((and (guard (string= "doc:update" event))
				(map path range lines))
		   (cesp--update-content path range lines))
		  ;; Cursor
		  ((and (guard (string= "cursor:move" event))
				(map id pos path name))
		   (cesp--render-cursor
			id pos path name))
		  ((and (guard (string= "cursor:range" event))
				(map id range path name))
		   (let* ((posses (seq-split range 2))
				 (pos1 (car posses))
				 (pos2 (car (cdr posses))))
			 (cesp--render-cursor
			  id pos1 path name pos2)))
		  ;; Users
		  ((and (guard (string= "user:join" event))
				(map name))
		   (message "%s joined" name))
		  ((and (guard (string= "user:leave" event))
				(map id name))
		   (message "%s left" name)
		   (cesp--delete-cursor id)))))))

(defun cesp--to-uint32(number)
  "Converts an Elisp number to an uint32."
  `(,(ash number -24)
	,(logand (ash number -16) #xff)
	,(logand (ash number -8) #xff)
	,(logand number #xff)))

(defun cesp--from-uint32(uint32)
  "Converts an uint32 into an Elisp number."
  (pcase-let (( `(,l1,l2,l3,l4) uint32 ))
	(+ (ash l1 24)
	   (ash l2 16)
	   (ash l3 8)
	   l4)))

(defun cesp--split-magic(data)
  "Splits DATA into Cesp packets via magic.
If unfinished packet, it's returned at the end.
If there is not an unfinished packet, return an extra
empty string. "
  ;; Get header
  (let ((packets nil)
		(interrupted nil))
	(while (not (string= data ""))
	  (condition-case err
		  (progn
			(let* ((header-size 6)
				   (header (encode-coding-string (substring data 0 header-size) 'utf-8))
				   (magic (substring header 0 2))
				   (payload-size (cesp--from-uint32 (append (substring header 2 6) nil)))
				   (payload (substring data header-size (+ header-size payload-size))))
			  ;; Leftovers
			  (setq data (substring data (+ header-size payload-size)))
			  (add-to-list 'packets payload t)))
		(args-out-of-range
		 (add-to-list 'packets data t)
		 (setq interrupted t)
		 (setq data ""))))
	(unless interrupted
	  (add-to-list 'packets data t))
	packets))

(defun cesp--sentinel(proc msg)
  "Sentinel function which will handle status change in connection.
PROC and MSG are used somehow, idk."
  (if (string= msg "connection broken by remote peer\n")
      (message (format "client %s has quit" proc))
	(message (concat "SENTINEL MESSAGE: "  msg))))

(defun cesp--open-file-menu(files)
  "Handler function which opens a menu to pick FILES."
  (cesp-get-file (completing-read
				  "Pick a file to open: "
				  files nil t)))

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
  (if-let ((mode (cdr (assoc (buffer-name) auto-mode-alist 'string-match-p))))
	  (funcall mode))
  ;; Initiate cesp-mode
  (cesp-mode 1)
  (setq-local cesp--initialized t))

(defun cesp--render-cursor(id position buffer name &optional startpos)
  "Renders cursor ID at POSITION in BUFFER.
ID is unique id for cursor, POSITION is a list
with a column and row. NAME is rendered next to the
cursor.
If STARTPOS is specified, the value between it
and position is highlighted."
  (let ((buf (get-buffer buffer)))
	(if buf
		(let* ((pos (save-excursion
					  (set-buffer buffer)
					  (cesp--point-from-pos (car position) (car (cdr position)))))
			   (pos2 (if startpos
						 (save-excursion
						   (set-buffer buffer)
						   (cesp--point-from-pos (car startpos) (car (cdr startpos))))
					   (1+ pos)))
			   (line-end (save-excursion
						   (save-restriction
							 (widen)
							 (goto-char (point-min))
							 (forward-line (car position))
							 (end-of-line)
							 (point))))
			   (overlay-pair (or (cdr (assoc id cesp-cursors))
								 (let ((c-o (make-overlay pos pos2 buf))
									   (n-o (make-overlay line-end (1- line-end) buf)))
								   (overlay-put c-o 'face 'cursor)
								   ;; This took over 3 hours
								   (overlay-put n-o 'after-string (concat " " (propertize (concat " " name) 'face 'cursor)))
								   (setq cesp-cursors (cons `(,id . (,c-o ,n-o)) cesp-cursors))
								   `(,c-o ,n-o)))))
		  ;; Update values
		  (move-overlay (car overlay-pair) pos pos2 buf)
		  (move-overlay (car (cdr overlay-pair)) line-end (1- line-end) buf)))))

(defun cesp--delete-cursor(client_id)
  "Deletes cursor CLIENT_ID."
  (dolist (o (cdr (assoc client_id cesp-cursors)))
	(delete-overlay o)
	(delete-overlay o))
  (setq cesp-cursors (map-delete cesp-cursors 1)))

(defun cesp--clear-cursors()
  "Deletes other peoples cursors.
Mainly for debugging but also used when
disconnected."
	(dolist (o cesp-cursors)
	  (delete-overlay (car (cdr o)))
	  (delete-overlay (car (cdr (cdr o)))))
	(setq cesp-cursors nil))

(defun cesp--update-content(path range lines)
  "Handler function which will apply change to buffer PATH.
If the specified buffer is not currently open, then
the changes are not applied.

RANGE is a list with two lines which map the bind the edit range.
LINES: List of the lines in the range as they are now"
  (let ((buffer (get-buffer path)))
	(if buffer
		(save-excursion ;; THIS ENTIRE BLOCK IS SUBJECT TO OPTIMIZATION
		  (set-buffer buffer)
		  (save-restriction
			(widen)
			(let ((first (car range))
				  (last (car (cdr range))))
			  ;; Goto first line
			  (goto-char (point-min))
			  (forward-line first)
			  ;; Replace lines iteratively
			  ;; (also make sure this doesn't trigger the cesp after-change hook)
			  (setq inhibit-modification-hooks t)
			  (dotimes (_ (- last first))
				(delete-line))
			  (dolist (line lines)
				(insert (concat line "\n")))
			  (setq inhibit-modification-hooks nil)))))))

;;; _
(advice-add 'save-buffer :before-until #'cesp--save-file)
;;(advice-remove 'save-buffer #'cesp--save-file)
(provide 'cesp)
;;; cesp.el ends here
