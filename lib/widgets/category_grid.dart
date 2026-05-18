import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/dispatcher_service.dart';

class CategoryGrid extends StatefulWidget {
  const CategoryGrid({super.key});

  @override
  State<CategoryGrid> createState() => _CategoryGridState();
}

class _CategoryGridState extends State<CategoryGrid> {
  String? _selectedCategory;

  static const List<Map<String, dynamic>> categories = [
    {
      'label': 'Sleep', 
      'emoji': '😴',
      'chips': ['Slept well', 'Poor sleep', 'Woke up twice', 'Insomnia']
    },
    {
      'label': 'Food', 
      'emoji': '🍎',
      'chips': ['Healthy meal', 'Late dinner', 'Fast food', 'Coffee']
    },
    {
      'label': 'Water', 
      'emoji': '💧',
      'chips': ['1 glass', '1 liter', 'Hydrated', 'Dehydrated']
    },
    {
      'label': 'Exercise', 
      'emoji': '🏃',
      'chips': ['Gym', 'Run', 'Walk', 'Yoga', 'Fencing']
    },
    {
      'label': 'Mood', 
      'emoji': '🧘',
      'chips': ['Stressed', 'Happy', 'Anxious', 'Calm']
    },
    {
      'label': 'Symptom', 
      'emoji': '🤒',
      'chips': ['Headache', 'Bloating', 'Pain', 'Nausea', 'Fatigue']
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final cat = categories[index];
            final isSelected = _selectedCategory == cat['label'];
            
            return InkWell(
              onTap: () {
                setState(() {
                  _selectedCategory = isSelected ? null : cat['label'];
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                  border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(cat['emoji']!, style: const TextStyle(fontSize: 28)),
                    const SizedBox(height: 8),
                    Text(cat['label']!, 
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white, 
                        fontSize: 13, 
                        fontWeight: FontWeight.bold
                      )),
                  ],
                ),
              ),
            );
          },
        ),
        if (_selectedCategory != null) ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories
                .firstWhere((c) => c['label'] == _selectedCategory)['chips']
                .map<Widget>((chip) => ActionChip(
                      backgroundColor: const Color(0xFF262626),
                      label: Text(chip, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      onPressed: () async {
                        // Quick log this chip with augmented context
                        final augmentedText = "Log ${chip.toLowerCase()}";
                        final now = DateTime.now();
                        
                        setState(() {
                          _selectedCategory = null;
                        });
                        
                        await context.read<DispatcherService>().handleInput(
                          augmentedText, 
                          timestamp: now
                        );
                      },
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}
