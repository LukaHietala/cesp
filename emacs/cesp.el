;;; cesp.el --- Live-share client for Emacs         -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Wisdurm

;; Author: Wisdurm <wisdurm@TheEngineer.TWOFORT>
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

(defgroup cespconf nil
  "Variables related to configuring Cesp"
  :group 'communication)

(defcustom cesp-name "Jaakko"
  "Your username on Cesp.
This is the name other users will see when
you are editing with them"
  :group 'cespconf
  :type '(string))

;;; Internal variables

(defvar cesp-server-process
  nil
  "The internal server process object.
This is the process object that represents
the connection to the tcp server")

;;; Public commands

;;;; Connection management

(defun cesp-connect-server(host port)
  "Connects to a Cesp server.
This connects your Emacs session to a Cesp server
at HOST PORT, for example localhost 8080
which is the default for a Cesp server.

It will then perform the handshake, giving your
name as per the variable"
  (interactive "sServer hostname: \nsServer port: ")
  (setq cesp-server-process (make-network-process
   :name "cesp-process"
   :buffer (get-buffer-create "*cesp*") ;; Don't think this does anything
   :host host
   :service port
   :family 'ipv4 ;; TODO: Support for ipv6
   :filter 'cesp-filter
   :sentinel 'cesp-sentinel))
  (cesp-client-forward '((event . "handshake") (name . "Jaakko")) ) ;; Perform handshake
  )

(defun cesp-disconnect()
  "Disconnects Emacs from the Cesp server.
This will disconnect the current Emacs client from
the Cesp server it is currently connected to, if
any"
  (interactive)
  (if (and cesp-server-process (process-live-p cesp-server-process))
	  (delete-process "cesp-process")
	(error "You are not connected to a server!")))

;;;; File handling

(defun cesp-get-files()
  "Sends a request to get the host's files
This will send a request_files event to the host.
This function does not handle the response"
  (interactive)
  (if (and cesp-server-process (process-live-p cesp-server-process))
	  (cesp-client-forward '((event . "request_files")))
	(error "You are not connected to a server!")))

;;; Internal functions

(defun cesp-client-forward(json-object)
  "Client sends the host a message formatted in Json.
This sends JSON to the host from a client connection.
Clients will only ever directly message the host.

JSON is an object that is parsed by json-serialize
into a string.
"
  (process-send-string cesp-server-process (concat (json-serialize json-object) "\n")))

;;;; Handlers

(defun cesp-filter(proc string)
  "Main function which parses Cesp input.
This function recieves all of the date recieved
by the tcp connection, and calls other functions,
as appropriate."
  (message string))

(defun cesp-sentinel(proc msg)
  "Sentinel function which handless statues changes in connection."
  (if (string= msg "connection broken by remote peer\n")
      (message (format "client %s has quit" proc))
	(message msg)))

;;; _
(provide 'cesp)
;;; cesp.el ends here
