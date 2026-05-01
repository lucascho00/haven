class ManualItem {
  const ManualItem({
    required this.id,
    required this.title,
    required this.category,
    required this.summary,
    required this.steps,
    required this.priority,
  });

  final String id;
  final String title;
  final String category;
  final String summary;
  final List<String> steps;
  final int priority;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'summary': summary,
    'steps': steps,
    'priority': priority,
  };

  factory ManualItem.fromJson(Map<dynamic, dynamic> json) => ManualItem(
    id: json['id'] as String,
    title: json['title'] as String,
    category: json['category'] as String,
    summary: json['summary'] as String,
    steps: (json['steps'] as List).cast<String>(),
    priority: json['priority'] as int,
  );
}
