import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:material_ui/material_ui.dart';

class SliderDialog extends StatefulWidget {
  const SliderDialog({
    super.key,
    required this.value,
    required this.title,
    required this.min,
    required this.max,
    this.divisions,
    this.suffix = '',
    this.precise = 1,
    this.minLabel,
    this.maxLabel,
    this.onChanged,
  });

  final double value;
  final Widget title;
  final double min;
  final double max;
  final int? divisions;
  final String suffix;
  final int precise;
  final String? minLabel;
  final String? maxLabel;
  final ValueChanged<double>? onChanged;

  @override
  State<SliderDialog> createState() => _SliderDialogState();
}

class _SliderDialogState extends State<SliderDialog> {
  late double _tempValue;

  @override
  void initState() {
    super.initState();
    _tempValue = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: widget.title,
      contentPadding: const .only(top: 20, left: 8, right: 8, bottom: 8),
      content: SizedBox(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 40,
              child: Slider(
                value: _tempValue,
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                label:
                    '${_tempValue.toStringAsFixed(widget.precise)}${widget.suffix}',
                onChanged: (double value) {
                  final nextValue = value.toPrecision(widget.precise);
                  setState(() {
                    _tempValue = nextValue;
                  });
                  widget.onChanged?.call(nextValue);
                },
              ),
            ),
            if (widget.minLabel != null || widget.maxLabel != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.minLabel ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    Text(
                      widget.maxLabel ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(
            '取消',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _tempValue),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
