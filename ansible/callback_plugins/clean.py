from ansible.plugins.callback import CallbackBase
import json

DOCUMENTATION = '''
name: clean
type: stdout
short_description: Clean status output
description: Minimal, clean output for homelab status playbooks
'''


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'stdout'
    CALLBACK_NAME = 'clean'

    def __init__(self):
        super().__init__()
        self._play = None
        self._task = None
        self.host_results = {}
        self.failures = []

    def v2_playbook_on_play_start(self, play):
        self._play = play
        name = play.get_name().strip()
        self._display.display(f"\n\033[1;36m{'=' * 50}\033[0m")
        self._display.display(f"\033[1;37m  {name}\033[0m")
        self._display.display(f"\033[1;36m{'=' * 50}\033[0m\n")

    def v2_playbook_on_task_start(self, task, is_conditional):
        self._task = task

    def v2_runner_on_ok(self, result):
        host = result._host.get_name()
        res = result._result

        if res.get('msg') and not res.get('ansible_facts'):
            msg = res['msg']
            if isinstance(msg, list):
                msg = '\n'.join(msg)
            self._display.display(f"  \033[1;32m✓\033[0m \033[1;37m{host:<20}\033[0m {msg}")
        elif res.get('ansible_facts'):
            pass

    def v2_runner_on_failed(self, result, ignore_errors=False):
        host = result._host.get_name()
        msg = result._result.get('msg', 'unknown error')
        if ignore_errors:
            self._display.display(f"  \033[1;33m!\033[0m \033[1;37m{host:<20}\033[0m {msg}")
        else:
            self._display.display(f"  \033[1;31m✗\033[0m \033[1;37m{host:<20}\033[0m {msg}")
            self.failures.append(host)

    def v2_runner_on_unreachable(self, result):
        host = result._host.get_name()
        self._display.display(f"  \033[1;31m✗\033[0m \033[1;37m{host:<20}\033[0m UNREACHABLE")
        self.failures.append(host)

    def v2_runner_on_skipped(self, result):
        host = result._host.get_name()
        self._display.display(f"  \033[0;33m-\033[0m \033[0;37m{host:<20}\033[0m skipped")

    def v2_playbook_on_stats(self, stats):
        hosts = sorted(stats.processed.keys())
        ok = sum(1 for h in hosts if not stats.failures.get(h) and not stats.dark.get(h))
        failed = sum(1 for h in hosts if stats.failures.get(h) or stats.dark.get(h))

        self._display.display(f"\n\033[1;36m{'─' * 50}\033[0m")
        if failed == 0:
            self._display.display(f"  \033[1;32m{ok}/{len(hosts)} hosts OK\033[0m\n")
        else:
            self._display.display(f"  \033[1;32m{ok} OK\033[0m | \033[1;31m{failed} FAILED\033[0m\n")

    def v2_on_file_diff(self, result):
        pass
