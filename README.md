# Card Game

A tiny deckbuilder in the style of *Slay the Spire*, made with **Godot 4.7** and
**GDScript**. It's deliberately small so every line can be read and understood.

![Screenshot of a battle](docs/screenshot.png)

![Screenshot of the character select screen](docs/character_select.png)

![Screenshot of the deck builder](docs/deck_builder.png)

**What's in it so far**

- A **Character Select** screen: each class (Adventurer, Knight) has its own deck-building rules
- A **deck builder** before each battle: pick which cards (and how many copies) go in your deck
- 12 cards across four schools (Strength, Agility, Intellect, Wisdom), made from a
  spreadsheet: `data/cards.csv` (see [Making cards from the spreadsheet](#making-cards-from-the-spreadsheet))
- Draw 5 cards each turn, with a draw pile and discard pile that reshuffles when empty
- 3 **energy** per turn; cards you can't afford are greyed out
- One enemy (a Slime) with HP that shows what it **intends** to do next turn
- Block that soaks up damage and disappears at the start of your next turn
- A turn loop (your turn, then the enemy's), plus a Victory / Defeat screen with Play Again and Change Deck buttons

---

## 1. Get the code onto your computer

Pick **one** of these. GitHub Desktop is recommended because it makes it easy
to get updates and save your own changes later.

### Option A: GitHub Desktop (recommended)

1. Download and install [GitHub Desktop](https://desktop.github.com/), then sign in with your GitHub account.
2. Choose **File → Clone repository...**
3. On the **GitHub.com** tab, pick `DustyOBrien/card-game`.
4. Leave the **Local path** as it is (usually `Documents\GitHub\card-game`) and click **Clone**.

Later, whenever new code is added on GitHub, click **Fetch origin** and then
**Pull origin** in GitHub Desktop to download it.

### Option B: Download ZIP (quickest, no extra software)

1. Go to the repo page on GitHub.
2. Click the green **Code** button, then **Download ZIP**.
3. Right-click the downloaded ZIP and choose **Extract All...**. Put the folder somewhere easy, like `Documents\card-game`.

With this option you won't get updates automatically; you'd download a fresh ZIP each time.

## 2. Open it in Godot

1. Start Godot. You'll see the **Project Manager** (the list of projects).
2. Click **Import**.
3. Browse to the `card-game` folder and select the `project.godot` file inside it.
4. Click **Import** (or **Import & Edit**). The editor opens.
5. Press **F5** (or the ▶ Play button at the top right) to play.

The first time you open the project, Godot creates a hidden `.godot` folder.
That's a cache that Godot can always rebuild, so it isn't saved to GitHub
(see `.gitignore`).

## 3. How to play

The game starts on **Character Select**. Your class decides which cards you can use:

| Class | Can use | Copies per card | Deck size |
|---|---|---|---|
| Adventurer | Strength, Agility, Intellect, Wisdom, Neutral | 1 (Neutral: 2) | 10 to 20 |
| Knight | Strength, Neutral | 3 (Neutral: 2) | 9 to 20 |

Then you're on the **deck builder**, holding your class's starter deck:

- Click a card on the left to add a copy to your deck. Click a line in **Your deck** on the right to take one copy out.
- **Clear** empties the deck; **Starter Deck** puts back the suggested deck (as many of each card as your class allows).
- When the deck is big enough, click **Start Battle**. **Change Class** goes back to Character Select.

In the battle:

- Click a card to play it. It costs energy (the yellow number in its corner).
- When you're out of energy or cards, click **End Turn**.
- The enemy then attacks for the number shown under its name. Your Block absorbs damage first.
- Bring the Slime to 0 HP to win.

---

## How the project is organized

```
card-game/
├── project.godot        Project settings (name, window size, which scene starts first)
├── scenes/
│   ├── character_select.tscn The first screen: pick a class
│   ├── deck_builder.tscn Pick the cards for your deck
│   ├── battle.tscn      The fight: enemy, player stats, hand, End Turn button
│   └── card.tscn        What ONE card looks like
├── scripts/
│   ├── game_state.gd    Autoload: keeps your class and deck while scenes change
│   ├── character_class.gd Defines what a class is (its deck rules)
│   ├── character_select.gd Shows one panel per class
│   ├── deck_builder.gd  Adding and removing cards, following your class's rules
│   ├── battle.gd        The rules: drawing, energy, turns, winning and losing
│   ├── card.gd          Makes a card show its data and report when it's clicked
│   ├── card_data.gd     Defines what information a card has (name, cost, damage...)
│   ├── combatant.gd     HP and Block for the player and the enemy
│   └── card_importer.gd Turns the spreadsheet into card files
├── tools/
│   └── import_cards.gd  Run this in the editor to re-import the spreadsheet
├── data/
│   └── cards.csv        The card spreadsheet (the master list of cards)
├── cards/               One .tres file per card, made by the importer
├── classes/             One .tres file per class (adventurer.tres, knight.tres)
└── docs/                Pictures for this README (Godot ignores this folder)
```

You may also see `.uid` and `.import` files. Godot makes these automatically
to keep track of files. Leave them alone and keep them in git.

## The four big ideas in Godot

### Nodes

A **node** is one building block that does one job. A `Label` shows text. A
`Button` can be clicked. An `HBoxContainer` lines up its children side by side.
A plain `Node` does nothing on its own, but you can give it a script.

Nodes are arranged in a **tree**: each node can have children. Open
`scenes/battle.tscn` and look at the **Scene** panel (top left) to see it:

```
Battle (Control)                 ← battle.gd is attached here
├── Player (Node)                ← combatant.gd: your HP and Block
├── Enemy (Node)                 ← combatant.gd: the Slime's HP and Block
├── Background (ColorRect)
├── Margin (MarginContainer)
│   └── Layout (VBoxContainer)   ← stacks everything top to bottom
│       ├── EnemyBox             ← enemy picture, name, HP, intent
│       ├── Spacer
│       ├── MessageLabel
│       ├── PlayerBar            ← HP, Block, Energy, piles, End Turn
│       └── Hand (HBoxContainer) ← cards get added here while playing
└── GameOverScreen               ← hidden until someone wins
```

### Scenes

A **scene** is a tree of nodes saved as a file (`.tscn`). Scenes can be used
inside other scenes, like a blueprint you can stamp out many times.

`card.tscn` is the blueprint for a single card. The battle script makes a
new copy of it for every card in your hand:

```gdscript
var card: Card = CARD_SCENE.instantiate()  # build a new card from the blueprint
hand_box.add_child(card)                   # put it in the Hand row
```

Double-click `card.tscn` in the **FileSystem** panel (bottom left) to open
and edit it on its own.

### Scripts

A **script** (`.gd` file) adds behaviour to a node. The first lines say what
kind of node it's for, e.g. `extends Button`. That's like inheriting from a
class in Python: the script *is* a Button, plus whatever we add.

Godot calls some functions for you automatically. The main one here is
`_ready()`, which runs once when the node appears. It's a lot like Python's
`__init__`.

### Signals

A **signal** is an announcement: "something just happened". Other nodes
**connect** a function to it, and that function runs every time the signal
is **emitted**. The node making the announcement doesn't need to know who's
listening.

This project uses signals in a chain when you click a card:

1. Godot's `Button` emits `pressed` when clicked.
2. `card.gd` hears that and emits its own `played` signal, passing along which card it is.
3. `battle.gd` hears `played`, spends energy, and calls `enemy.take_damage(6)`.
4. `combatant.gd` lowers HP and emits `stats_changed`.
5. `battle.gd` hears `stats_changed` and updates the labels on screen.

Connecting in code looks like this (from `battle.gd`):

```gdscript
player.died.connect(_on_player_died)   # "when the player dies, run _on_player_died"
```

You can also connect signals without code, in the editor's **Node** tab (next
to the Inspector). This project connects them in code so you can see them all
in one place.

### Switching scenes, and autoloads

The game has two screens, and each one is its own scene. Moving between them is one line:

```gdscript
get_tree().change_scene_to_file("res://scenes/battle.tscn")
```

That throws the current scene away (and every variable in it!) and loads the
new one. So how does the battle know which deck you built? It's kept in an
**autoload**: a script Godot creates once when the game starts and never throws
away. This project has one, `game_state.gd`, registered under the name
`GameState` in **Project → Project Settings → Globals → Autoload**. Any script
can use it by name:

```gdscript
GameState.deck.append(card)              # deck builder: add a card
draw_pile = GameState.deck.duplicate()   # battle: copy the deck, then shuffle the copy
```

Keep autoloads small: only things that really must outlive a scene belong there
(later: the player's HP between fights, gold, which floor you're on...).

### Bonus idea: Resources and card data

`card_data.gd` defines a **Resource**, which is Godot's name for a piece of
data saved as a file. Each file in `cards/` (like `strike.tres`) is one of them. Click
one in the FileSystem panel and you can change its cost, damage, or colour in
the **Inspector** on the right. (Changes made there are overwritten the next time you import the spreadsheet, so the spreadsheet is the place for lasting changes.)

Every card has these fields:

| Field | What it is |
|---|---|
| Card Name | The name at the top of the card |
| Cost | Energy needed to play it |
| Types | Checkboxes: **Attack** (deals damage), **Defense** (gains Block), **Ability** (other effects, like drawing a card). A card can have several. |
| Schools | Checkboxes: **Strength**, **Agility**, **Intellect**, **Wisdom**. A card can have several, or none (Neutral). Shown as STR / AGI / INT / WIS for now. |
| Damage | Damage dealt to the enemy |
| Block | Block the player gains |
| Heal | HP the player gets back (can't go above max HP) |
| Draw | Cards the player draws |
| Discard | Random cards thrown from the player's hand into the discard pile |
| Draw If Full HP | Cards drawn only if you were at full HP when you played it (Pray) |
| Next Attack Bonus | Extra damage for your next Attack card (Rage) |
| Next Defense Bonus | Extra Block for your next Defense card (Brace) |
| Copies | Not used right now (each class builds its own starter deck) |
| Effect | The rules text printed on the card (typed by hand) |
| Color | The card's background colour |

Types and Schools use **bit flags**: each option is a power of two (1, 2, 4, 8)
and the card stores them added together, so Attack + Ability is 1 + 4 = 5.
The comments in `card_data.gd` explain this, and the helpers
`has_type()` / `has_school()` do the checking for you:

```gdscript
if card.has_type(CardData.CardType.ATTACK):
	print("This card is an attack!")
```

## How a turn works (in `battle.gd`)

```
start_battle()
  └─ copy the deck you built (GameState.deck), shuffle, then start_player_turn()

start_player_turn()
  ├─ clear the player's Block, refill energy to 3
  ├─ choose the enemy's next attack (shown as its "intent")
  └─ draw_cards(5)

You click cards  →  _on_card_played()
  └─ pay energy, deal damage / gain block, move the card to the discard pile

You click End Turn  →  _on_end_turn_pressed()
  ├─ move the rest of your hand to the discard pile
  ├─ enemy_turn(): short pause, then the enemy attacks
  └─ start_player_turn() again (unless someone's HP hit 0)
```

## GDScript for Python people

| Python                       | GDScript                              |
|------------------------------|---------------------------------------|
| `def attack(amount):`        | `func attack(amount: int) -> void:`   |
| `x = 5`                      | `var x := 5`                          |
| `MAX = 3` (by convention)    | `const MAX := 3`                      |
| `None`                       | `null`                                |
| `True` / `False`             | `true` / `false`                      |
| `for i in range(5):`         | `for i in 5:`                         |
| `len(my_list)`               | `my_list.size()`                      |
| `my_list.pop()`              | `my_list.pop_back()`                  |
| `random.shuffle(my_list)`    | `my_list.shuffle()`                   |
| `f"HP {hp}/{max_hp}"`        | `"HP %d / %d" % [hp, max_hp]`         |
| `self.hp`                    | `hp` (`self.` is optional)            |
| `import` a class             | `class_name` makes it available everywhere |

Indentation works just like in Python (this project uses tabs). The `: int`
and `-> void` bits are optional type hints, like Python's. They help Godot
catch mistakes and autocomplete for you.

## Things to try next

Small changes, roughly easiest first:

1. **Tweak numbers.** Change a card's numbers in the spreadsheet and re-import, or the Slime's `max_hp` by clicking the **Enemy** node in `battle.tscn`.
2. **Change a class's deck rules.** Click `classes/knight.tres` in the FileSystem panel and change the numbers in the Inspector. Or make a new class (see [Adding a class](#adding-a-class)).
3. **Change the enemy's attacks.** Edit `ENEMY_MIN_ATTACK` / `ENEMY_MAX_ATTACK` at the top of `battle.gd`.
4. **Make a new card.** Add a row to the spreadsheet and re-import (see below).
5. **Show HP as a bar** using a `ProgressBar` node instead of a label.
6. **Give the enemy a second move**, like sometimes gaining Block instead of attacking.
7. **Add a card reward** after winning, so your deck grows: that's the "deckbuilding" part!

## Making cards from the spreadsheet

All cards live in one spreadsheet, `data/cards.csv`. The game doesn't read the
spreadsheet directly; an **importer** turns each row into a card file in `cards/`.

**To change cards:**

1. Edit your spreadsheet and export it as CSV (Google Sheets: **File → Download → Comma-separated values**).
2. Save it over `data/cards.csv` in the project folder (same name).
3. In Godot, double-click `tools/import_cards.gd`, then in the Script editor choose **File → Run** (Ctrl+Shift+X).
4. The **Output** panel at the bottom lists every card it made. Press F5 to play.

**Columns** (the order doesn't matter, and capital letters don't matter):

| Column | Example | Notes |
|---|---|---|
| NAME | Quick Strike | Also used for the file name (`quick_strike.tres`) |
| Copies | 2 | Not used right now (each class builds its own starter deck) |
| Cost | 1 | |
| School | Strength, Wisdom | Several allowed, separated by `,` or `/`. Blank = Neutral |
| Type | Attack | Attack, Defense, Ability. Several allowed, like School |
| Description | Deal 6 Damage | The text printed on the card |
| Attack | 6 | Damage dealt |
| Block | 6 | Block gained |
| Draw | 2 | Cards drawn |
| Discard | 2 | Random cards discarded from your hand |
| Heal | 3 | HP healed |
| Draw If Full HP | 1 | Cards drawn if you were at full HP |
| Next Attack Bonus | 3 | Added to your next Attack card's damage |
| Next Defense Bonus | 3 | Added to your next Defense card's Block |

Blank cells count as 0. The "Card" column is ignored (NAME is used instead).

**The spreadsheet is the boss:** any card file in `cards/` that isn't in the
spreadsheet gets deleted when you import. So make new cards by adding rows,
not by duplicating `.tres` files in Godot.

## Adding a class

Classes are data, just like cards: each one is a `.tres` file in `classes/`,
made from `character_class.gd`. To add one, you don't write any code:

1. In the **FileSystem** panel, right-click `classes/knight.tres` and choose **Duplicate...**. Name it, e.g. `rogue.tres`.
2. Click the new file. In the **Inspector**, change:
   - **Display Name**, **Description**, **Color**
   - **Sort Order**: where it appears on Character Select (lower = further left)
   - **Deck Rules**: which **Allowed Schools** are ticked, **Allow Neutral**, **Max Copies** (school cards), **Max Copies Neutral**, **Min / Max Deck Size**
3. Press F5. The new class is on Character Select, and its rules text is written for you from those numbers.

## Saving your own changes to GitHub (GitHub Desktop)

1. Make changes in Godot and save (Ctrl+S).
2. In GitHub Desktop, you'll see the changed files on the left.
3. Type a short summary at the bottom left (e.g. "Make Strike deal 7 damage") and click **Commit to main**.
4. Click **Push origin** to upload it to GitHub.
