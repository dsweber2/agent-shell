;;; agent-shell-letta.el --- Letta Code agent configuration -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Matias Forbord

;; Author: Matias Forbord
;; URL: https://github.com/xenodium/agent-shell

;; This package is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This package is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; This file includes Letta Code-specific configurations.
;;
;; Letta agents are stateful: they keep long-term memory across
;; sessions and conversations.  This integration drives Letta Code
;; through the `letta-code-acp' adapter, which wraps
;; `letta -p --output-format stream-json'.
;;
;; Letta-specific notes:
;;
;; - A Letta agent has a persistent "main chat" conversation plus any
;;   number of side conversations.  `agent-shell-letta-start-main-chat'
;;   attaches to the former; `agent-shell-letta-start-conversation'
;;   spawns a fresh one.
;; - Set `agent-shell-letta-agent-id' to pin shells to a specific agent.
;;

;;; Code:

(eval-when-compile
  (require 'cl-lib))
(require 'shell-maker)
(require 'acp)

(declare-function agent-shell--indent-string "agent-shell")
(declare-function agent-shell-make-agent-config "agent-shell")
(autoload 'agent-shell-make-agent-config "agent-shell")
(declare-function agent-shell--make-acp-client "agent-shell")
(declare-function agent-shell--dwim "agent-shell")

(defcustom agent-shell-letta-acp-command
  '("letta-code-acp")
  "Command and parameters for the Letta Code ACP adapter.

The first element is the command name, and the rest are command parameters."
  :type '(repeat string)
  :group 'agent-shell)

(defcustom agent-shell-letta-environment
  nil
  "Environment variables for the Letta Code ACP adapter.

This should be a list of \"NAME=VALUE\" strings, typically built with
`agent-shell-make-environment-variables'.  Use it to inject
LETTA_API_KEY for Letta Cloud, or leave credentials to the adapter's
own environment for local backends."
  :type '(repeat string)
  :group 'agent-shell)

(defcustom agent-shell-letta-agent-id
  nil
  "Optional Letta agent ID to pin shell sessions to.

When nil, the adapter lets `letta' pick an agent (resume last, or
create a new one)."
  :type '(choice (const :tag "Let adapter choose" nil)
                 (string :tag "Agent ID"))
  :group 'agent-shell)

(defcustom agent-shell-letta-model
  nil
  "Optional Letta model handle (e.g. \"auto\")."
  :type '(choice (const :tag "Default" nil)
                 (string :tag "Model handle"))
  :group 'agent-shell)

(defcustom agent-shell-letta-permission-mode
  nil
  "Optional Letta permission mode.

When non-nil, passed to the adapter via the LETTA_PERMISSION_MODE
environment variable so the spawned `letta -p' uses it."
  :type '(choice (const :tag "Letta default (unrestricted)" nil)
                 (const "standard")
                 (const "acceptEdits")
                 (const "unrestricted")
                 (const "memory"))
  :group 'agent-shell)

(defcustom agent-shell-letta-conversation-id
  nil
  "Default Letta conversation to attach to on session start.

Set to an explicit \"conv-...\" id to resume that conversation
\(in which case `agent-shell-letta-agent-id' is ignored; headless
derives the agent from the conversation).  Set to \"default\" to
attach to the agent's main chat.

When nil (the default), the start command decides: the agent's main
chat via `agent-shell-letta-start-main-chat' or a fresh conversation
via `agent-shell-letta-start-conversation'."
  :type '(choice (const :tag "Honor the start command (default)" nil)
                 (const :tag "Agent's main chat" "default")
                 (string :tag "Explicit conversation id"))
  :group 'agent-shell)

(defun agent-shell-letta-make-agent-config ()
  "Create a Letta Code agent configuration.

Returns an agent configuration alist using `agent-shell-make-agent-config'."
  (agent-shell-make-agent-config
   :identifier 'letta
   :mode-line-name "Letta"
   :buffer-name "Letta"
   :shell-prompt "Letta> "
   :shell-prompt-regexp "Letta> "
   :welcome-function #'agent-shell-letta--welcome-message
   :client-maker (lambda (buffer)
                   (agent-shell-letta-make-client :buffer buffer))
   :install-instructions
   "Install the adapter with 'npm install -g letta-code-acp', or
customize `agent-shell-letta-acp-command' to point at a local build,
e.g. '(\"node\" \"/path/to/letta-code-acp/dist/cli.js\")."))

(defun agent-shell-letta-start-agent ()
  "Start an interactive Letta Code agent shell."
  (interactive)
  (agent-shell--dwim :config (agent-shell-letta-make-agent-config)
                     :new-shell t))

(defun agent-shell-letta-start-main-chat ()
  "Start a Letta Code agent shell attached to the agent's main chat.

The main chat is the persistent top-level conversation for the pinned
agent (`agent-shell-letta-agent-id').  Shells opened with this command
attach to the same conversation and share its memory."
  (interactive)
  (let ((agent-shell-letta-conversation-id "default"))
    (agent-shell--dwim :config (agent-shell-letta-make-agent-config)
                       :new-shell t)))

(defun agent-shell-letta-start-conversation ()
  "Start a Letta Code agent shell in a fresh conversation.

Spawns a new conversation under the pinned agent
\(`agent-shell-letta-agent-id'), separate from the agent's main chat
and from any other shell."
  (interactive)
  (let ((agent-shell-letta-conversation-id nil))
    (agent-shell--dwim :config (agent-shell-letta-make-agent-config)
                       :new-shell t)))

(cl-defun agent-shell-letta-make-client (&key buffer)
  "Create a Letta Code ACP client with BUFFER as context."
  (unless buffer
    (error "Missing required argument: :buffer"))
  (let ((environment (copy-sequence (or agent-shell-letta-environment (list)))))
    (when agent-shell-letta-agent-id
      (push (format "LETTA_AGENT_ID=%s" agent-shell-letta-agent-id)
            environment))
    (when agent-shell-letta-model
      (push (format "LETTA_MODEL=%s" agent-shell-letta-model)
            environment))
    (when agent-shell-letta-permission-mode
      (push (format "LETTA_PERMISSION_MODE=%s" agent-shell-letta-permission-mode)
            environment))
    (when agent-shell-letta-conversation-id
      (push (format "LETTA_CONVERSATION_ID=%s" agent-shell-letta-conversation-id)
            environment))
    (agent-shell--make-acp-client :command (car agent-shell-letta-acp-command)
                                  :command-params (cdr agent-shell-letta-acp-command)
                                  :environment-variables environment
                                  :context-buffer buffer)))

(defun agent-shell-letta--welcome-message (config)
  "Return Letta welcome message using `shell-maker' CONFIG."
  (let ((art (agent-shell--indent-string 4 (agent-shell-letta--ascii-art)))
        (message (string-trim-left (shell-maker-welcome-message config) "\n")))
    (concat "\n\n"
            art
            "\n\n"
            message)))

(defun agent-shell-letta--ascii-art ()
  "Letta ASCII art."
  (let* ((is-dark (eq (frame-parameter nil 'background-mode) 'dark))
         (text (string-trim "
  ██╗     ███████╗████████╗████████╗ █████╗
  ██║     ██╔════╝╚══██╔══╝╚══██╔══╝██╔══██╗
  ██║     █████╗     ██║      ██║   ███████║
  ██║     ██╔══╝     ██║      ██║   ██╔══██║
  ███████╗███████╗   ██║      ██║   ██║  ██║
  ╚══════╝╚══════╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝
" "\n")))
    (propertize text 'font-lock-face (if is-dark
                                         '(:foreground "#7fb3ff" :inherit fixed-pitch)
                                       '(:foreground "#2a5db0" :inherit fixed-pitch)))))

(provide 'agent-shell-letta)

;;; agent-shell-letta.el ends here
