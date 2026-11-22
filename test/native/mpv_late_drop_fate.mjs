import { readFileSync } from 'node:fs';
import { strictEqual } from 'node:assert';

const input = JSON.parse(
  readFileSync(new URL('../fixtures/mpv_frame_drop_policy/late-output.json', import.meta.url), 'utf8'),
);
const reference = readFileSync(new URL('../ref/fate/mpv-late-output-drop', import.meta.url), 'utf8');
const { instance } = await WebAssembly.instantiate(readFileSync(process.argv[2]));
const {
  replace_output: replaceOutput,
  catchup_after_rate_change: catchupAfterRateChange,
  release_can_drop: releaseCanDrop,
  release_output_wait_us: releaseOutputWait,
  texture_drop_recovery: textureDropRecovery,
} = instance.exports;
const output = input.map(([name, ...args]) => {
  const verify = args.length === 4 ? replaceOutput : catchupAfterRateChange;
  return `${name} ${verify(...args)}`;
});
const cadenceCases = JSON.parse(
  readFileSync(new URL('../fixtures/mpv_frame_drop_policy/release-cadence.json', import.meta.url), 'utf8'),
);
for (const [name, operation, ...args] of cadenceCases) {
  const result = {
    'release-drop': releaseCanDrop,
    'release-wait': releaseOutputWait,
    'texture-drop': (...values) => String(textureDropRecovery(...values)).padStart(2, '0'),
  }[operation](...args);
  output.push(`${name} ${result}`);
}
const actual = output.join('\n') + '\n';
strictEqual(actual, reference.replaceAll('\r\n', '\n'));
process.stdout.write(actual);
