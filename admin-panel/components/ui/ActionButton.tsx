'use client';

import { Button } from './Button';

type Props = React.ComponentProps<typeof Button>;
export function ActionButton(props: Props) {
  return <Button {...props} />;
}
