(() => {
    const root = document.getElementById("blackjack");
    const stateLabel = document.getElementById("state-label");
    const timer = document.getElementById("timer");
    const actions = document.getElementById("actions");
    const leaveModal = document.getElementById("confirm-leave");
    const cardStylePicker = document.getElementById("card-style-picker");
    const cardStyleOptions = document.getElementById("card-style-options");
    const cameraButton = document.getElementById("camera-button");
    const scaleInput = document.getElementById("ui-scale");
    const scaleValue = document.getElementById("ui-scale-value");
    const propEditor = document.getElementById("prop-editor");
    const propGizmo = document.getElementById("prop-gizmo");
    const gizmoOrigin = document.getElementById("gizmo-origin");
    let game = null;
    let pendingAction = false;
    let panelScale = 1;
    let cameraLookActive = false;
    let firstPersonActive = false;

    const SCALE_MIN = 1;
    const SCALE_CAP = 1.5;
    let preferredScale = SCALE_MIN;
    let gizmoProjection = null;
    let draggedAxis = null;
    let draggedMode = null;
    let lastPointer = null;
    let lastRotationAngle = null;
    let queuedDelta = 0;
    let dragFrame = null;

    function postNui(action, payload = {}) {
        const resource = typeof GetParentResourceName === "function" ? GetParentResourceName() : "Nt_BlackJack";
        return fetch(`https://${resource}/${action}`, {
            method: "POST",
            headers: { "Content-Type": "application/json; charset=UTF-8" },
            body: JSON.stringify(payload),
        }).catch(() => {});
    }

    function stopCameraLook() {
        if (!cameraLookActive) return;
        cameraLookActive = false;
        postNui("cameraLook", { active: false });
    }

    window.addEventListener("mousedown", (event) => {
        if (event.button !== 2
            || root.classList.contains("hidden")
            || !propEditor.classList.contains("hidden")) return;
        event.preventDefault();
        cameraLookActive = true;
        postNui("cameraLook", {
            active: true,
            x: event.clientX / window.innerWidth,
            y: event.clientY / window.innerHeight,
        });
    }, true);

    window.addEventListener("mouseup", (event) => {
        if (event.button === 2) stopCameraLook();
    }, true);

    window.addEventListener("contextmenu", (event) => {
        if (!root.classList.contains("hidden")) event.preventDefault();
    });

    function renderGizmo(data) {
        gizmoProjection = data?.visible ? data : null;
        propGizmo.style.visibility = gizmoProjection ? "visible" : "hidden";
        if (!gizmoProjection) return;
        const originX = data.origin.x * window.innerWidth;
        const originY = data.origin.y * window.innerHeight;
        gizmoOrigin.setAttribute("cx", originX);
        gizmoOrigin.setAttribute("cy", originY);
        ["x", "y", "z"].forEach((axis) => {
            const group = propGizmo.querySelector(`[data-mode="translate"][data-axis="${axis}"]`);
            const endpoint = data.axes?.[axis];
            group.style.display = endpoint?.visible ? "block" : "none";
            if (!endpoint?.visible) return;
            const endX = endpoint.x * window.innerWidth;
            const endY = endpoint.y * window.innerHeight;
            const line = group.querySelector("line");
            const handle = group.querySelector("circle");
            line.setAttribute("x1", originX);
            line.setAttribute("y1", originY);
            line.setAttribute("x2", endX);
            line.setAttribute("y2", endY);
            handle.setAttribute("cx", endX);
            handle.setAttribute("cy", endY);

            const rotation = propGizmo.querySelector(`[data-mode="rotate"][data-axis="${axis}"]`);
            const ring = data.rings?.[axis];
            rotation.style.display = ring?.visible ? "block" : "none";
            if (ring?.visible) {
                rotation.querySelector("polyline").setAttribute("points", ring.points
                    .map((point) => `${point.x * window.innerWidth},${point.y * window.innerHeight}`)
                    .join(" "));
            }
        });
    }

    function flushGizmoDrag() {
        dragFrame = null;
        if (!draggedAxis || !draggedMode || !queuedDelta) return;
        const delta = queuedDelta;
        queuedDelta = 0;
        postNui("propGizmoDrag", {
            mode: draggedMode,
            axis: draggedAxis,
            pixels: draggedMode === "translate" ? delta : 0,
            degrees: draggedMode === "rotate" ? delta : 0,
        });
    }

    propGizmo.addEventListener("pointerdown", (event) => {
        const group = event.target.closest("[data-axis]");
        if (!group || !gizmoProjection) return;
        draggedAxis = group.dataset.axis;
        draggedMode = group.dataset.mode;
        lastPointer = { x: event.clientX, y: event.clientY };
        if (draggedMode === "rotate") {
            const originX = gizmoProjection.origin.x * window.innerWidth;
            const originY = gizmoProjection.origin.y * window.innerHeight;
            lastRotationAngle = Math.atan2(event.clientY - originY, event.clientX - originX);
        }
        group.setPointerCapture?.(event.pointerId);
        event.preventDefault();
    });

    window.addEventListener("pointermove", (event) => {
        if (!draggedAxis || !lastPointer || !gizmoProjection) return;
        const origin = gizmoProjection.origin;
        if (draggedMode === "translate") {
            const endpoint = gizmoProjection.axes?.[draggedAxis];
            if (!endpoint?.visible) return;
            const axisX = (endpoint.x - origin.x) * window.innerWidth;
            const axisY = (endpoint.y - origin.y) * window.innerHeight;
            const length = Math.hypot(axisX, axisY);
            if (length > 0.001) {
                const mouseX = event.clientX - lastPointer.x;
                const mouseY = event.clientY - lastPointer.y;
                queuedDelta += (mouseX * axisX + mouseY * axisY) / length;
            }
        } else if (draggedMode === "rotate") {
            const originX = origin.x * window.innerWidth;
            const originY = origin.y * window.innerHeight;
            const angle = Math.atan2(event.clientY - originY, event.clientX - originX);
            if (lastRotationAngle !== null) {
                let delta = angle - lastRotationAngle;
                if (delta > Math.PI) delta -= Math.PI * 2;
                if (delta < -Math.PI) delta += Math.PI * 2;
                queuedDelta += delta * 180 / Math.PI;
            }
            lastRotationAngle = angle;
        }
        if (queuedDelta && !dragFrame) dragFrame = window.requestAnimationFrame(flushGizmoDrag);
        lastPointer = { x: event.clientX, y: event.clientY };
        event.preventDefault();
    });

    window.addEventListener("pointerup", () => {
        if (dragFrame) {
            window.cancelAnimationFrame(dragFrame);
            dragFrame = null;
            flushGizmoDrag();
        }
        draggedAxis = null;
        draggedMode = null;
        lastPointer = null;
        lastRotationAngle = null;
        queuedDelta = 0;
    });

    try {
        preferredScale = Math.min(SCALE_CAP, Math.max(SCALE_MIN, Number(localStorage.getItem("nt-blackjack-ui-scale")) || SCALE_MIN));
    } catch (_) {}

    function setPanelScale(value, persist = false) {
        panelScale = Math.min(SCALE_CAP, Math.max(SCALE_MIN, Number(value) || SCALE_MIN));
        document.documentElement.style.setProperty("--ui-scale", String(panelScale));
        scaleInput.value = String(Math.round(panelScale * 100));
        scaleValue.textContent = `${Math.round(panelScale * 100)}%`;

        if (persist) {
            preferredScale = panelScale;
            try {
                localStorage.setItem("nt-blackjack-ui-scale", String(panelScale));
            } catch (_) {}
        }
    }

    function getPanelScaleLimit(panel) {
        const rect = panel.getBoundingClientRect();
        if (!rect.width || !rect.height) return SCALE_CAP;

        const margin = 8;
        const viewportWidth = window.innerWidth;
        const viewportHeight = window.innerHeight;
        const baseWidth = rect.width / panelScale;
        const baseHeight = rect.height / panelScale;
        const centerX = (rect.left + rect.right) / 2;
        const centerY = (rect.top + rect.bottom) / 2;
        let horizontalLimit;
        let verticalLimit;

        if (panel.classList.contains("players-panel")) {
            horizontalLimit = (viewportWidth - margin - rect.left) / baseWidth;
            verticalLimit = (viewportHeight - margin - rect.top) / baseHeight;
        } else if (panel.classList.contains("action-panel")) {
            horizontalLimit = (rect.right - margin) / baseWidth;
            verticalLimit = (2 * Math.min(centerY - margin, viewportHeight - margin - centerY)) / baseHeight;
        } else if (panel.classList.contains("dealer-zone")) {
            horizontalLimit = (2 * Math.min(centerX - margin, viewportWidth - margin - centerX)) / baseWidth;
            verticalLimit = (viewportHeight - margin - rect.top) / baseHeight;
        } else {
            horizontalLimit = (2 * Math.min(centerX - margin, viewportWidth - margin - centerX)) / baseWidth;
            verticalLimit = (rect.bottom - margin) / baseHeight;
        }

        return Math.max(SCALE_MIN, Math.min(horizontalLimit, verticalLimit));
    }

    function updateScaleLimit() {
        if (root.classList.contains("hidden")) return;

        const panels = root.querySelectorAll(".players-panel, .action-panel, .dealer-zone, .player-zone");
        let safeMaximum = SCALE_CAP;
        panels.forEach((panel) => {
            safeMaximum = Math.min(safeMaximum, getPanelScaleLimit(panel));
        });

        const safePercent = Math.max(100, Math.floor((safeMaximum * 100) / 5) * 5);
        scaleInput.max = String(safePercent);
        setPanelScale(Math.min(preferredScale, safePercent / 100));
    }

    const stateNames = {
        WAITING: "Waiting",
        BETTING: "Place bets",
        DEALING: "Dealing",
        PLAYER_TURNS: "Player turns",
        DEALER_TURN: "Dealer turn",
        SETTLEMENT: "Results",
    };

    const escapeHtml = (value) => String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");

    const money = (value) => `$${Math.round(Number(value) || 0)}`;

    const cardImages = {
        "Blackwater": { folder: "Blackwater", ending: "Bla" },
        "Valentine": { folder: "Valentine", ending: "Val" },
        "Saint Denis": { folder: "Saint Denis", ending: "Std" },
        "Rhodes": { folder: "Rhodes", ending: "Rho" },
        "Camp": { folder: "Camp", ending: "Camp" },
        "Vanhorn": { folder: "Vanhorn", ending: "Van" },
        "RRS": { folder: "RRS", ending: "RRS" },
        "New": { folder: "New", ending: "New" },
    };

    function cardPath(card) {
        const image = cardImages[game.cardStyle];
        const deckFolder = image.folder.replaceAll(" ", "_");
        if (!card || !card.isRevealed) return `img/card/${deckFolder}/Back_${image.ending}.png`;
        const royalty = card.royalty === "T" ? "10" : card.royalty;
        return `img/card/${deckFolder}/${royalty}_${card.suit.toUpperCase()}_${image.ending}.png`;
    }

    function cardsHtml(cards, className = "card") {
        if (!cards || !cards.length) return '<span class="muted">No cards dealt</span>';
        return cards.map((card) =>
            className === "mini-card"
                ? `<span class="mini-card-crop"><img class="mini-card" src="${cardPath(card)}" alt="${card?.isRevealed ? escapeHtml(card.royalty + card.suit) : "Hidden card"}"></span>`
                : `<img class="${className}" src="${cardPath(card)}" alt="${card?.isRevealed ? escapeHtml(card.royalty + card.suit) : "Hidden card"}">`
        ).join("");
    }

    function resultText(hand) {
        if (!hand.result) return hand.status === "ACTIVE" ? "Playing" : hand.status;
        const payout = hand.payout > 0 ? ` · ${money(hand.payout)} returned` : "";
        return `${hand.result}${payout}`;
    }

    let actionTimeout = null;

    async function send(action, payload = {}) {
        if (pendingAction) return;
        pendingAction = true;
        renderActions();
        let waitMs = 2500;
        try {
            const resource = typeof GetParentResourceName === "function" ? GetParentResourceName() : "Nt_BlackJack";
            const response = await fetch(`https://${resource}/${action}`, {
                method: "POST",
                headers: { "Content-Type": "application/json; charset=UTF-8" },
                body: JSON.stringify(payload),
            });
            const result = await response.json().catch(() => ({}));
            waitMs = Math.max(0, Number(result?.waitMs) || waitMs);
        } catch (_) {
            pendingAction = false;
            renderActions();
        }
        if (actionTimeout !== null) window.clearTimeout(actionTimeout);
        actionTimeout = window.setTimeout(() => {
            actionTimeout = null;
            pendingAction = false;
            renderActions();
        }, waitMs);
    }

    function playerHandValue(hand) {
        if (!hand || !hand.cards?.length) return "-";
        if (hand.value === undefined || hand.value === null) return "?";
        return `${hand.value}${hand.isSoft ? " soft" : ""}`;
    }

    function compactHandsHtml(player) {
        const hands = player.hands || [];
        if (!hands.length) return '<div class="player-row-empty muted">No cards</div>';
        return hands.map((hand, index) => `
            <div class="player-row-hand ${player.activeHandIndex === index + 1 ? "active" : ""}">
                <div class="mini-cards">${cardsHtml(hand.cards, "mini-card")}</div>
                <div class="mini-value">
                    <span>${hands.length > 1 ? "Split " + (index + 1) : "Hand"}</span>
                    <strong>${escapeHtml(playerHandValue(hand))}</strong>
                </div>
            </div>
        `).join("");
    }

    function renderPlayers() {
        const rows = game?.players || [];
        document.getElementById("player-count").textContent = String(rows.length);
        document.getElementById("players-list").innerHTML = rows.map((player) => {
            const isSelf = player.source === game.self.source;
            const hand = player.hands?.[player.activeHandIndex - 1] || player.hands?.[0];
            const status = player.waiting
                ? "Next hand"
                : hand
                    ? (hand.result || hand.status)
                    : (player.bet > 0 ? "Bet locked" : "Betting");
            return `
                <article class="player-row ${player.isCurrent ? "current" : ""} ${isSelf ? "self" : ""} ${player.isNpc ? "npc" : ""}">
                    <div class="player-row-head">
                        <strong>Seat ${player.seatIndex}</strong>
                        <span>${escapeHtml(player.name)}${isSelf ? " (You)" : player.isNpc ? " (NPC)" : ""}</span>
                    </div>
                    <div class="player-row-meta">
                        <span>${escapeHtml(status || "")}</span>
                        <span>${money(player.bet)}</span>
                    </div>
                    <div class="player-row-hands">${compactHandsHtml(player)}</div>
                </article>
            `;
        }).join("");
    }

    function renderHands() {
        const hands = game?.self?.hands || [];
        const container = document.getElementById("player-hands");
        if (!hands.length) {
            container.innerHTML = '<div class="action-message">Place a bet to receive cards.</div>';
            return;
        }
        container.innerHTML = hands.map((hand, index) => `
            <article class="hand ${game.isMyTurn && game.self.activeHandIndex === index + 1 ? "active" : ""}">
                <div class="hand-title">
                    <span>${hands.length > 1 ? `Hand ${index + 1}` : "Hand"}</span>
                    <strong>${hand.value}${hand.isSoft ? " soft" : ""}</strong>
                    <span>${money(hand.bet)}</span>
                </div>
                <div class="cards">${cardsHtml(hand.cards)}</div>
                <div class="result ${escapeHtml(hand.result || "")}">${escapeHtml(resultText(hand))}</div>
            </article>
        `).join("");
    }

    function renderActions() {
        if (!game) return;
        const allowed = game.allowedActions || {};
        if (allowed.placeBet) {
            actions.innerHTML = `
                <div class="bet-box">
                    <label for="bet-amount">Wager amount</label>
                    <input id="bet-amount" type="number" min="${game.rules.minBet}" max="${game.rules.maxBet}" step="${game.rules.betStep}" value="${game.rules.minBet}">
                    <button class="action-button" data-action="placeBet" ${pendingAction ? "disabled" : ""}>Place bet</button>
                </div>
            `;
        } else if (game.isMyTurn) {
            actions.innerHTML = `
                <button class="action-button" data-action="hit" ${!allowed.hit || pendingAction ? "disabled" : ""}>Hit</button>
                <button class="action-button" data-action="stand" ${!allowed.stand || pendingAction ? "disabled" : ""}>Stand</button>
                <button class="action-button" data-action="double" ${!allowed.double || pendingAction ? "disabled" : ""}>Double down</button>
                <button class="action-button" data-action="split" ${!allowed.split || pendingAction ? "disabled" : ""}>Split</button>
            `;
        } else {
            const messages = {
                WAITING: "Waiting for the next betting round.",
                BETTING: game.self.waiting ? "You will enter on the next hand." : "Waiting for other players to finish betting.",
                DEALING: "The dealer is dealing the opening cards.",
                PLAYER_TURNS: game.currentName ? `Waiting for ${escapeHtml(game.currentName)}.` : "Waiting for the next player.",
                DEALER_TURN: "The dealer is completing the house hand.",
                SETTLEMENT: "Results are being settled. The next hand will begin shortly.",
            };
            actions.innerHTML = `<div class="action-message">${messages[game.state] || "Waiting…"}</div>`;
        }

        const betAmount = document.getElementById("bet-amount");
        if (betAmount) {
            betAmount.addEventListener("input", () => {
                if (Number(betAmount.value) > game.rules.maxBet) {
                    betAmount.value = game.rules.maxBet;
                }
            });
        }

        actions.querySelectorAll("[data-action]").forEach((button) => {
            button.addEventListener("click", () => {
                const action = button.dataset.action;
                if (action === "placeBet") {
                    const input = document.getElementById("bet-amount");
                    const amount = Math.min(Number(input?.value), game.rules.maxBet);
                    if (input) input.value = amount;
                    if (!Number.isInteger(amount) || amount < game.rules.minBet || amount > game.rules.maxBet || amount % game.rules.betStep !== 0) {
                        return;
                    }
                    send("placeBet", { amount, roundId: game.roundId });
                    return;
                }
                send(action, { roundId: game.roundId });
            });
        });
    }

    function render() {
        if (!game) return;
        document.getElementById("table-name").textContent = game.tableLabel || "Blackjack";
        document.getElementById("player-name").textContent = game.self?.name || "Player";
        document.getElementById("cash-value").textContent = money(game.self?.cash);
        document.getElementById("minimum-bet").textContent = money(game.rules?.minBet);
        document.getElementById("maximum-bet").textContent = money(game.rules?.maxBet);
        document.getElementById("bet-step").textContent = money(game.rules?.betStep);
        document.getElementById("outline-max-bet").textContent = money(game.rules?.maxBet);
        document.getElementById("outline-bet-step").textContent = money(game.rules?.betStep);
        document.getElementById("payout-label").textContent = game.rules?.blackjackPayout === 1.5 ? "3 TO 2" : `${game.rules?.blackjackPayout || 1.5} TO 1`;
        document.getElementById("dealer-rule").textContent = game.rules?.dealerHitsSoft17 ? "Hits on soft 17" : "Stands on soft 17";
        document.getElementById("dealer-total").textContent = game.dealer?.revealed
            ? `Total ${game.dealer.value}${game.dealer.isSoft ? " soft" : ""}`
            : `Showing ${game.dealer?.value || 0}`;
        document.getElementById("dealer-cards").innerHTML = cardsHtml(game.dealer?.cards);
        document.getElementById("shoe-cards").textContent = `${game.cardsRemaining || 0} cards in shoe`;
        document.getElementById("shuffle-status").textContent = `${game.handsSinceShuffle || 0} hands since shuffle`;
        document.getElementById("turn-banner").textContent = game.isMyTurn
            ? "Your turn"
            : game.currentName
                ? `${game.currentName}'s turn`
                : (stateNames[game.state] || "Waiting");
        stateLabel.textContent = stateNames[game.state] || game.state;
        renderPlayers();
        renderHands();
        renderActions();
        updateTimer();
    }

    function setFirstPerson(active) {
        firstPersonActive = active === true;
        root.classList.toggle("first-person", firstPersonActive);
        cameraButton.textContent = firstPersonActive ? "Return camera" : "First-person camera";
        window.requestAnimationFrame(updateScaleLimit);
    }

    function showCardStylePicker(styles) {
        cardStyleOptions.innerHTML = (styles || []).map((style) =>
            `<button class="action-button" type="button" data-card-style="${escapeHtml(style)}">${escapeHtml(style)}</button>`
        ).join("");
        cardStyleOptions.querySelectorAll("[data-card-style]").forEach((button) => {
            button.addEventListener("click", () => {
                postNui("selectCardStyle", { style: button.dataset.cardStyle });
                cardStylePicker.classList.add("hidden");
            });
        });
        cardStylePicker.classList.remove("hidden");
    }

    function updateTimer() {
        if (!game?.deadline) {
            timer.textContent = "";
            return;
        }
        const remaining = Math.max(0, Math.ceil(game.deadline - Date.now() / 1000));
        timer.textContent = `${remaining}s`;
    }

    window.addEventListener("message", (event) => {
        if (event.data?.type === "open") {
            root.classList.remove("hidden");
            window.requestAnimationFrame(updateScaleLimit);
        } else if (event.data?.type === "state") {
            game = event.data.game;
            root.classList.remove("hidden");
            render();
            window.requestAnimationFrame(updateScaleLimit);
        } else if (event.data?.type === "close") {
            if (actionTimeout !== null) {
                window.clearTimeout(actionTimeout);
                actionTimeout = null;
            }
            if (dragFrame) {
                window.cancelAnimationFrame(dragFrame);
                dragFrame = null;
            }
            game = null;
            pendingAction = false;
            cameraLookActive = false;
            setFirstPerson(false);
            draggedAxis = null;
            draggedMode = null;
            lastPointer = null;
            lastRotationAngle = null;
            queuedDelta = 0;
            leaveModal.classList.add("hidden");
            cardStylePicker.classList.add("hidden");
            root.classList.add("hidden");
        } else if (event.data?.type === "chooseCardStyle") {
            showCardStylePicker(event.data.styles);
        } else if (event.data?.type === "propEditorOpen") {
            propEditor.classList.remove("hidden");
        } else if (event.data?.type === "propEditorClose") {
            propEditor.classList.add("hidden");
            draggedAxis = null;
            draggedMode = null;
            lastPointer = null;
            lastRotationAngle = null;
            queuedDelta = 0;
        } else if (event.data?.type === "propGizmoUpdate") {
            renderGizmo(event.data);
        } else if (event.data?.type === "cameraLook" && event.data.active === false) {
            cameraLookActive = false;
        }
    });

    function showLeaveModal() {
        leaveModal.classList.remove("hidden");
    }

    document.getElementById("leave-button").addEventListener("click", showLeaveModal);
    cameraButton.addEventListener("click", async () => {
        const response = await postNui("toggleFirstPerson");
        const result = await response?.json().catch(() => null);
        if (result) setFirstPerson(result.active);
    });
    document.getElementById("cancel-leave").addEventListener("click", () => leaveModal.classList.add("hidden"));
    document.getElementById("confirm-leave-button").addEventListener("click", () => {
        leaveModal.classList.add("hidden");
        send("requestLeave");
    });
    scaleInput.addEventListener("input", () => setPanelScale(Number(scaleInput.value) / 100, true));
    window.addEventListener("resize", () => window.requestAnimationFrame(updateScaleLimit));
    window.addEventListener("keyup", (event) => {
        if (event.key === "Escape" && !propEditor.classList.contains("hidden")) {
            postNui("propGizmoClose");
            return;
        }
        if (event.key === "Escape" && !root.classList.contains("hidden") && cardStylePicker.classList.contains("hidden")) showLeaveModal();
    });
    setPanelScale(preferredScale);
    window.setInterval(updateTimer, 250);
})();
