part of ace;

class Point {
  
  final int row;
  
  final int column;
  
  /// Constructs a new [Point] with the given [row] and [column].
  const Point(this.row, this.column);
  
  /// Constructs a new [Point] that is a copy of the given [other].
  Point.copy(Point other) : this(other.row, other.column);
   
  bool operator ==(Object other) {
    if(identical(this, other)) return true;
    if(other is! Point) return false; 
    final o = other;
    return row == o.row && column == o.column;
  }  
  
  int get hashCode => row.hashCode ^ column.hashCode;
  
  String toString() => 'Point: [${row}/${column}]';
}
