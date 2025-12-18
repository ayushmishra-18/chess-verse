import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For compute
import 'package:chess/chess.dart' as chess_lib;
import 'dart:async';
import 'dart:math';

// ---------------------------------------------------------------------------
// 1. Independent AI Isolate Function
// ---------------------------------------------------------------------------

// This function runs in a separate thread. It receives a FEN string and Depth.
Map<String, String>? isolateComputerMove(Map<String, dynamic> params) {
  final String fen = params['fen'].toString();
  final int depth = params['depth'] as int;

  final game = chess_lib.Chess.fromFEN(fen);

  if (game.game_over) return null;

  // Get moves. Note: We use verbose: true to get Maps/Objects, not just strings.
  final dynamic moves = game.moves({'verbose': true});

  if (moves is! List || moves.isEmpty) return null;

  // 0 = Random, 1 = Greedy, 2+ = Minimax
  if (depth == 0) {
    final move = moves[Random().nextInt(moves.length)];
    return _extractMoveParams(move);
  }

  // Minimax
  MoveScore best = _minimax_iso(game, depth, -999999, 999999, true);

  if (best.move == null) {
    // Fallback to random
    final move = moves[Random().nextInt(moves.length)];
    return _extractMoveParams(move);
  }

  return _extractMoveParams(best.move);
}

// Helper to safely extract 'from' and 'to' from dynamic move objects (Map or Move)
Map<String, String> _extractMoveParams(dynamic move) {
  String from = '';
  String to = '';
  String promotion = 'q';

  if (move is Map) {
    if (move['from'] != null) from = move['from'].toString();
    if (move['to'] != null) to = move['to'].toString();
    if (move['promotion'] != null) promotion = move['promotion'].toString();
  } else if (move is chess_lib.Move) {
    // FIXED: Explicitly call .toString() on all properties to handle Object/dynamic types safely
    from = move.fromAlgebraic.toString();
    to = move.toAlgebraic.toString();
    promotion = move.promotion?.toString() ?? 'q';
  }

  return {
    'from': from,
    'to': to,
    'promotion': promotion
  };
}

class MoveScore {
  final int score;
  final dynamic move; // Changed from Move? to dynamic to handle Maps/Objects
  MoveScore({required this.score, this.move});
}

// Simplified Piece Values for Isolate
const Map<String, int> isoPieceValues = {
  'p': 100, 'n': 320, 'b': 330, 'r': 500, 'q': 900, 'k': 20000,
};

// Simplified Center Bonus for Isolate
const List<double> isoCenterBonus = [
  0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
  0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
  0.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0,
  0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0,
  0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0,
  0.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0,
  0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
  0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
];

MoveScore _minimax_iso(chess_lib.Chess game, int depth, int alpha, int beta, bool isMaximizing) {
  if (depth == 0 || game.game_over) {
    return MoveScore(score: _evaluateBoard_iso(game), move: null);
  }

  // Request verbose moves to get objects/maps
  final dynamic moves = game.moves({'verbose': true});

  if (moves is! List) return MoveScore(score: 0, move: null);

  if (isMaximizing) {
    int maxEval = -999999;
    dynamic bestMove;
    for (var move in moves) {
      game.move(move);
      int eval = _minimax_iso(game, depth - 1, alpha, beta, false).score;
      game.undo();
      if (eval > maxEval) {
        maxEval = eval;
        bestMove = move;
      }
      alpha = max(alpha, eval);
      if (beta <= alpha) break;
    }
    return MoveScore(score: maxEval, move: bestMove);
  } else {
    int minEval = 999999;
    dynamic bestMove;
    for (var move in moves) {
      game.move(move);
      int eval = _minimax_iso(game, depth - 1, alpha, beta, true).score;
      game.undo();
      if (eval < minEval) {
        minEval = eval;
        bestMove = move;
      }
      beta = min(beta, eval);
      if (beta <= alpha) break;
    }
    return MoveScore(score: minEval, move: bestMove);
  }
}

int _evaluateBoard_iso(chess_lib.Chess game) {
  int totalEvaluation = 0;
  for (int i = 0; i < 8; i++) {
    for (int j = 0; j < 8; j++) {
      String square = "${String.fromCharCode('a'.codeUnitAt(0) + j)}${i + 1}";
      final piece = game.get(square);
      if (piece != null) {
        int value = isoPieceValues[piece.type.name.toLowerCase()] ?? 0;
        value += (isoCenterBonus[i * 8 + j] * 10).toInt();
        if (piece.color == chess_lib.Color.BLACK) totalEvaluation += value;
        else totalEvaluation -= value;
      }
    }
  }
  return totalEvaluation;
}

// ---------------------------------------------------------------------------
// 2. Main Logic
// ---------------------------------------------------------------------------

class GameLogic {
  late chess_lib.Chess _game;
  final List<String> _historySan = [];

  GameLogic() {
    _game = chess_lib.Chess();
  }

  void reset() {
    _game = chess_lib.Chess();
    _historySan.clear();
  }

  List<List<chess_lib.Piece?>> get board2D {
    List<List<chess_lib.Piece?>> board = [];
    for (int rank = 0; rank < 8; rank++) {
      List<chess_lib.Piece?> row = [];
      for (int file = 0; file < 8; file++) {
        String squareName = "${String.fromCharCode('a'.codeUnitAt(0) + file)}${rank + 1}";
        row.add(_game.get(squareName));
      }
      board.add(row);
    }
    return board;
  }

  String get fen => _game.fen;
  chess_lib.Color get turn => _game.turn;
  bool get hasStarted => _historySan.isNotEmpty;
  List<String> get history => List.unmodifiable(_historySan);

  bool attemptMove(String from, String to, [String? promotion]) {
    final dynamic moveResult = _game.move({
      'from': from, 'to': to, 'promotion': promotion ?? 'q'
    });

    if (moveResult != null) {
      String moveString = "$from$to";
      if (moveResult is Map && moveResult.containsKey('san')) {
        moveString = moveResult['san'].toString();
      } else if (promotion != null) {
        moveString += promotion;
      }
      _historySan.add(moveString);
      return true;
    }
    return false;
  }

  List<String> getValidMoves(String square) {
    final dynamic moves = _game.moves({'square': square, 'verbose': true});
    if (moves is List) {
      return moves.map<String>((m) {
        if (m is Map) return m['to']?.toString() ?? '';
        if (m is chess_lib.Move) return m.toAlgebraic.toString();
        return '';
      }).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  bool isPromotionMove(String from, String to) {
    final piece = _game.get(from);
    if (piece == null || piece.type != chess_lib.PieceType.PAWN) return false;
    if (piece.color == chess_lib.Color.WHITE) return to.endsWith('8');
    else return to.endsWith('1');
  }

  Map<String, List<chess_lib.PieceType>> getCapturedPieces() {
    final initialCounts = {
      chess_lib.PieceType.PAWN: 8, chess_lib.PieceType.ROOK: 2,
      chess_lib.PieceType.KNIGHT: 2, chess_lib.PieceType.BISHOP: 2,
      chess_lib.PieceType.QUEEN: 1, chess_lib.PieceType.KING: 1,
    };
    final whiteBoardCounts = <chess_lib.PieceType, int>{};
    final blackBoardCounts = <chess_lib.PieceType, int>{};

    for (var rank in board2D) {
      for (var piece in rank) {
        if (piece != null) {
          if (piece.color == chess_lib.Color.WHITE) whiteBoardCounts[piece.type] = (whiteBoardCounts[piece.type] ?? 0) + 1;
          else blackBoardCounts[piece.type] = (blackBoardCounts[piece.type] ?? 0) + 1;
        }
      }
    }

    List<chess_lib.PieceType> whiteCaptured = [];
    List<chess_lib.PieceType> blackCaptured = [];

    initialCounts.forEach((type, count) {
      int wOnBoard = whiteBoardCounts[type] ?? 0;
      int bOnBoard = blackBoardCounts[type] ?? 0;
      for (int i = 0; i < count - wOnBoard; i++) whiteCaptured.add(type);
      for (int i = 0; i < count - bOnBoard; i++) blackCaptured.add(type);
    });

    int value(chess_lib.PieceType t) {
      switch(t) {
        case chess_lib.PieceType.PAWN: return 1;
        case chess_lib.PieceType.KNIGHT: return 3;
        case chess_lib.PieceType.BISHOP: return 3;
        case chess_lib.PieceType.ROOK: return 5;
        case chess_lib.PieceType.QUEEN: return 9;
        default: return 0;
      }
    }
    whiteCaptured.sort((a, b) => value(a).compareTo(value(b)));
    blackCaptured.sort((a, b) => value(a).compareTo(value(b)));
    return {"capturedByBlack": whiteCaptured, "capturedByWhite": blackCaptured};
  }

  bool get inCheck => _game.in_check;
  bool get isGameOver => _game.game_over;
  bool get isCheckmate => _game.in_checkmate;
  bool get isDraw => _game.in_draw;
}

// ---------------------------------------------------------------------------
// 3. UI Layer
// ---------------------------------------------------------------------------

void main() {
  runApp(const ChessApp());
}

class AppTheme {
  final Color lightSquare;
  final Color darkSquare;
  final String name;
  const AppTheme(this.name, this.lightSquare, this.darkSquare);
}

class ChessApp extends StatefulWidget {
  const ChessApp({super.key});
  @override
  State<ChessApp> createState() => _ChessAppState();
}

class _ChessAppState extends State<ChessApp> {
  int _currentThemeIndex = 0;
  final List<AppTheme> themes = [
    const AppTheme("Classic Green", Color(0xFFEBECD0), Color(0xFF779556)),
    const AppTheme("Tournament Brown", Color(0xFFF0D9B5), Color(0xFFB58863)),
    const AppTheme("Ice Blue", Color(0xFFDEE3E6), Color(0xFF8CA2AD)),
  ];

  void _cycleTheme() {
    setState(() {
      _currentThemeIndex = (_currentThemeIndex + 1) % themes.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Chess',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF81B64C)),
      ),
      home: GamePage(
          theme: themes[_currentThemeIndex],
          onThemeChanged: _cycleTheme
      ),
    );
  }
}

class GamePage extends StatelessWidget {
  final AppTheme theme;
  final VoidCallback onThemeChanged;

  const GamePage({super.key, required this.theme, required this.onThemeChanged});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Flutter Chess"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.palette),
            onPressed: onThemeChanged,
            tooltip: "Change Board Theme",
          ),
        ],
      ),
      body: SafeArea(
        child: ChessBoardWidget(theme: theme),
      ),
    );
  }
}

class ChessBoardWidget extends StatefulWidget {
  final AppTheme theme;
  const ChessBoardWidget({super.key, required this.theme});

  @override
  State<ChessBoardWidget> createState() => _ChessBoardWidgetState();
}

class _ChessBoardWidgetState extends State<ChessBoardWidget> {
  late GameLogic game;
  List<String> validMoves = [];
  String? selectedSquare;

  Timer? _timer;
  Duration whiteTime = const Duration(minutes: 10);
  Duration blackTime = const Duration(minutes: 10);
  bool _timerRunning = false;

  bool isVsComputer = true;
  int aiDifficulty = 0;
  bool isComputerThinking = false;

  @override
  void initState() {
    super.initState();
    game = GameLogic();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNewGameDialog();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    if (_timerRunning) return;
    _timerRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (game.isGameOver) {
        timer.cancel();
        return;
      }
      setState(() {
        if (game.turn == chess_lib.Color.WHITE) whiteTime -= const Duration(seconds: 1);
        else blackTime -= const Duration(seconds: 1);
      });
      if (whiteTime.inSeconds <= 0 || blackTime.inSeconds <= 0) {
        timer.cancel();
        _showGameOverDialog(timeout: true);
      }
    });
  }

  void _resetGame(bool vsComputer, [int difficulty = 0]) {
    setState(() {
      game.reset();
      validMoves.clear();
      selectedSquare = null;
      whiteTime = const Duration(minutes: 10);
      blackTime = const Duration(minutes: 10);
      _timer?.cancel();
      _timerRunning = false;
      isVsComputer = vsComputer;
      aiDifficulty = difficulty;
      isComputerThinking = false;
    });
  }

  void _playMoveSound() {
    debugPrint("🎵 Clack!");
  }

  Future<void> _triggerComputerMove() async {
    if (!isVsComputer || game.isGameOver || game.turn != chess_lib.Color.BLACK) return;

    setState(() { isComputerThinking = true; });

    int depth = aiDifficulty == 0 ? 0 : (aiDifficulty == 1 ? 2 : 3);
    final params = {'fen': game.fen, 'depth': depth};

    Map<String, String>? move;
    try {
      move = await compute(isolateComputerMove, params);
    } catch (e) {
      debugPrint("AI Error: $e");
    }

    if (!mounted) return;

    if (move != null) {
      _makeMove(move['from']!, move['to']!, move['promotion']);
    }

    if (mounted) setState(() { isComputerThinking = false; });
  }

  Future<void> _makeMove(String from, String to, [String? autoPromotion]) async {
    String? promotionPart = autoPromotion;
    bool isHumanTurn = !isVsComputer || game.turn == chess_lib.Color.WHITE;

    if (game.isPromotionMove(from, to) && promotionPart == null && isHumanTurn) {
      promotionPart = await _showPromotionDialog();
      if (promotionPart == null) return;
    }

    bool success = game.attemptMove(from, to, promotionPart);

    if (success) {
      _playMoveSound();
      if (!_timerRunning) _startTimer();

      setState(() {
        selectedSquare = null;
        validMoves = [];
      });

      if (game.isGameOver) {
        _timer?.cancel();
        _showGameOverDialog();
      } else {
        if (isVsComputer && game.turn == chess_lib.Color.BLACK) {
          _triggerComputerMove();
        }
      }
    } else {
      if (isHumanTurn) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Invalid move: $from -> $to"), duration: const Duration(milliseconds: 500)),
        );
      }
    }
  }

  Future<String?> _showPromotionDialog() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Center(child: Text("Promote to:")),
        content: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _promotionOption("queen", "q"),
              const SizedBox(width: 8),
              _promotionOption("rook", "r"),
              const SizedBox(width: 8),
              _promotionOption("bishop", "b"),
              const SizedBox(width: 8),
              _promotionOption("knight", "n"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _promotionOption(String name, String code) {
    final color = game.turn == chess_lib.Color.WHITE ? "white" : "black";
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(code),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(8),
            color: Colors.black12,
          ),
          child: Image.asset("assets/pieces/${color}_$name.png", width: 40, height: 40),
        ),
      ),
    );
  }

  void _showNewGameDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SimpleDialog(
        title: const Text("New Game", textAlign: TextAlign.center),
        contentPadding: const EdgeInsets.all(16),
        children: [
          const Text("Vs Computer", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          _buildModeButton("Easy (Random)", () { Navigator.pop(context); _resetGame(true, 0); }),
          _buildModeButton("Medium (Normal)", () { Navigator.pop(context); _resetGame(true, 1); }),
          _buildModeButton("Hard (Pro)", () { Navigator.pop(context); _resetGame(true, 2); }, color: Colors.redAccent),
          const Divider(height: 24),
          _buildModeButton("Pass & Play (Vs Friend)", () { Navigator.pop(context); _resetGame(false); }, color: Colors.blueGrey),
        ],
      ),
    );
  }

  Widget _buildModeButton(String text, VoidCallback onTap, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? const Color(0xFF81B64C),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(text),
      ),
    );
  }

  void _showGameOverDialog({bool timeout = false}) {
    String title = "Game Over";
    String content = "Draw";

    if (timeout) {
      title = "Time's Up!";
      content = "${game.turn == chess_lib.Color.WHITE ? "Black" : "White"} wins on time!";
    } else if (game.isCheckmate) {
      title = "Checkmate!";
      content = "${game.turn == chess_lib.Color.WHITE ? "Black" : "White"} wins!";
    } else if (game.isDraw) {
      content = "Draw by Stalemate or Insufficient Material";
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showNewGameDialog();
            },
            child: const Text("New Game"),
          ),
        ],
      ),
    );
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF262421),
      builder: (context) => MoveHistorySheet(history: game.history),
    );
  }

  void _onSquareClicked(String square, chess_lib.Piece? piece) {
    if (isVsComputer && isComputerThinking) return;

    if (selectedSquare != null) {
      if (selectedSquare == square) {
        setState(() { selectedSquare = null; validMoves = []; });
        return;
      }
      _makeMove(selectedSquare!, square);
      return;
    }

    if (piece != null) {
      if (isVsComputer && piece.color != chess_lib.Color.WHITE) return;
      if (piece.color == game.turn) {
        setState(() {
          selectedSquare = square;
          validMoves = game.getValidMoves(square);
        });
      }
    }
  }

  void _handleDrop(String from, String to) {
    if (isVsComputer && isComputerThinking) return;
    _makeMove(from, to);
  }

  @override
  Widget build(BuildContext context) {
    final captured = game.getCapturedPieces();
    String opponentName = isVsComputer
        ? (aiDifficulty == 0 ? "Bot (Easy)" : aiDifficulty == 1 ? "Bot (Medium)" : "Bot (Hard)")
        : "Opponent";

    return Column(
      children: [
        PlayerInfoWidget(
          isPlayer: false, time: blackTime, isActive: game.turn == chess_lib.Color.BLACK,
          capturedPieces: captured["capturedByBlack"]!, onHistoryTap: _showHistory, isBot: isVsComputer, name: opponentName,
        ),

        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final squareSize = constraints.maxWidth / 8;
                    final boardGrid = game.board2D;

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: BoardPainter(
                              lightColor: widget.theme.lightSquare,
                              darkColor: widget.theme.darkSquare,
                            ),
                          ),
                        ),
                        ..._buildBoardSquares(squareSize, boardGrid),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        PlayerInfoWidget(
          isPlayer: true, time: whiteTime, isActive: game.turn == chess_lib.Color.WHITE,
          capturedPieces: captured["capturedByWhite"]!, onHistoryTap: _showHistory, name: "You",
        ),
      ],
    );
  }

  List<Widget> _buildBoardSquares(double squareSize, List<List<chess_lib.Piece?>> grid) {
    List<Widget> squares = [];
    final pieceTypeMap = {
      chess_lib.PieceType.PAWN: "pawn", chess_lib.PieceType.ROOK: "rook",
      chess_lib.PieceType.KNIGHT: "knight", chess_lib.PieceType.BISHOP: "bishop",
      chess_lib.PieceType.QUEEN: "queen", chess_lib.PieceType.KING: "king",
    };

    for (int rank = 0; rank < 8; rank++) {
      for (int file = 0; file < 8; file++) {
        final squareName = "${String.fromCharCode('a'.codeUnitAt(0) + file)}${rank + 1}";
        final piece = grid[rank][file];
        final isHighlight = validMoves.contains(squareName);
        final isSelected = selectedSquare == squareName;

        // Base square (Hitbox for dropping)
        squares.add(
          Positioned(
            left: file * squareSize,
            bottom: rank * squareSize,
            width: squareSize,
            height: squareSize,
            child: DragTarget<String>(
              onWillAccept: (data) => true,
              onAccept: (fromSquare) => _handleDrop(fromSquare, squareName),
              builder: (context, candidateData, rejectedData) {
                final isHovering = candidateData.isNotEmpty;
                // Draw Highlights
                if (isSelected) {
                  return Container(color: Colors.yellow.withOpacity(0.5));
                }
                if (isHighlight) {
                  // If capture, show ring, else dot
                  if (piece != null) {
                    return Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.black26, width: 4), borderRadius: BorderRadius.circular(50)),
                    );
                  }
                  return Center(
                    child: Container(width: squareSize * 0.3, height: squareSize * 0.3, decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle)),
                  );
                }
                if (isHovering) return Container(color: Colors.white.withOpacity(0.5));
                return const SizedBox(); // Invisible drop target
              },
            ),
          ),
        );

        // Render Pieces (with Animation)
        if (piece != null) {
          final colorName = piece.color == chess_lib.Color.WHITE ? "white" : "black";
          final typeName = pieceTypeMap[piece.type] ?? "pawn";
          final assetName = 'assets/pieces/${colorName}_${typeName}.png';

          bool canDrag = piece.color == game.turn;
          if (isVsComputer && piece.color != chess_lib.Color.WHITE) canDrag = false;

          Widget pieceWidget = Image.asset(assetName);
          if (canDrag) {
            pieceWidget = Draggable<String>(
              data: squareName,
              feedback: Transform.scale(
                scale: 1.2,
                child: SizedBox(width: squareSize, height: squareSize, child: Image.asset(assetName)),
              ),
              childWhenDragging: Opacity(opacity: 0.5, child: Image.asset(assetName)),
              child: Image.asset(assetName),
            );
          }

          // Use AnimatedPositioned for smooth sliding
          squares.add(
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              left: file * squareSize,
              bottom: rank * squareSize,
              width: squareSize,
              height: squareSize,
              child: GestureDetector(
                onTap: () => _onSquareClicked(squareName, piece),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  child: pieceWidget,
                ),
              ),
            ),
          );
        }
      }
    }
    return squares;
  }
}

class BoardPainter extends CustomPainter {
  final Color lightColor;
  final Color darkColor;
  BoardPainter({required this.lightColor, required this.darkColor});
  @override
  void paint(Canvas canvas, Size size) {
    final squareSize = size.width / 8;
    final paint = Paint();
    for (var rank = 0; rank < 8; rank++) {
      for (var file = 0; file < 8; file++) {
        final isLight = (rank + file) % 2 == 0;
        paint.color = isLight ? lightColor : darkColor;
        canvas.drawRect(Rect.fromLTWH(file * squareSize, rank * squareSize, squareSize, squareSize), paint);
      }
    }
  }
  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) =>
      oldDelegate.lightColor != lightColor || oldDelegate.darkColor != darkColor;
}

// ---------------------------------------------------------------------------
// 5. Info Widgets
// ---------------------------------------------------------------------------

class PlayerInfoWidget extends StatelessWidget {
  final bool isPlayer;
  final Duration time;
  final bool isActive;
  final List<chess_lib.PieceType> capturedPieces;
  final VoidCallback onHistoryTap;
  final bool isBot;
  final String name;

  const PlayerInfoWidget({
    super.key, required this.isPlayer, required this.time, required this.isActive,
    required this.capturedPieces, required this.onHistoryTap, this.isBot = false, this.name = "Player",
  });

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    final pieceTypeMap = {
      chess_lib.PieceType.PAWN: "pawn", chess_lib.PieceType.ROOK: "rook",
      chess_lib.PieceType.KNIGHT: "knight", chess_lib.PieceType.BISHOP: "bishop",
      chess_lib.PieceType.QUEEN: "queen",
    };
    final capturedColor = isPlayer ? "black" : "white";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFF262421),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isPlayer ? Colors.green : Colors.grey,
            radius: 20,
            child: Icon(isBot ? Icons.computer : Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (isPlayer) GestureDetector(onTap: onHistoryTap, child: const Icon(Icons.history, color: Colors.grey, size: 20)),
                ]),
                SizedBox(
                  height: 20,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: capturedPieces.length,
                    itemBuilder: (context, index) {
                      final type = capturedPieces[index];
                      final name = pieceTypeMap[type];
                      if (name == null) return const SizedBox();
                      return Image.asset("assets/pieces/${capturedColor}_$name.png", width: 20, height: 20);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: isActive ? Colors.white : Colors.black26, borderRadius: BorderRadius.circular(4)),
            child: Text(_formatDuration(time), style: TextStyle(color: isActive ? Colors.black : Colors.white54, fontSize: 20, fontFamily: "monospace", fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class MoveHistorySheet extends StatelessWidget {
  final List<String> history;
  const MoveHistorySheet({super.key, required this.history});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: 400,
      child: Column(
        children: [
          const Text("Move History", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(color: Colors.grey),
          Expanded(
            child: history.isEmpty
                ? const Center(child: Text("No moves yet.", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
              itemCount: (history.length / 2).ceil(),
              itemBuilder: (context, index) {
                final moveNum = index + 1;
                final whiteMove = history[index * 2];
                final blackMove = (index * 2 + 1 < history.length) ? history[index * 2 + 1] : "";
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 40, child: Text("$moveNum.", style: const TextStyle(color: Colors.grey))),
                      Expanded(child: Text(whiteMove, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      Expanded(child: Text(blackMove, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}