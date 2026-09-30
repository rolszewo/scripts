#!/opt/saltstack/salt/bin/python3
import sys
import salt.config
import salt.utils.event
from argparse import ArgumentParser
from pprint import pformat

def main():
    parser = ArgumentParser(description="Listen to Salt Master events with optional tag filtering")
    parser.add_argument('-t', '--tag', type=str, default=None,
                        help='Filter events by a specific tag (e.g., "salt/minion/*" or "vault/unsealtoken/renewed_*")')
    
    args = parser.parse_args()
    
    try:
        opts = salt.config.master_config('/etc/salt/master')
        sock_dir = opts['sock_dir']
        
        # Initialize the event listener
        event_bus = salt.utils.event.MasterEvent(sock_dir, opts=opts)
        
        print(f"Listening for Salt events (Tag filter: {args.tag})...")
        
        while True:
            try:
                event = event_bus.get_event(full=True, auto_reconnect=True)
                
                if not event:
                    continue  # Skip empty events
                
                # Apply tag filtering
                if args.tag and not event['tag'].startswith(args.tag):
                    continue
                
                print(f"\nEvent Tag: {event['tag']}")
                print("Data:")
                print(pformat(event['data']))
            
            except KeyboardInterrupt:
                print("\nExiting gracefully...")
                break
            
            except Exception as e:
                print(f"Error processing event: {str(e)}")
    
    except FileNotFoundError:
        print("Error: Could not load Salt master configuration. Ensure '/etc/salt/master' exists.")
        sys.exit(1)
    
    except KeyError as e:
        print(f"Missing configuration key in /etc/salt/master: {e}")
        sys.exit(2)

if __name__ == "__main__":
    main()