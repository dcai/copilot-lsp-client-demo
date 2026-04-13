export const buildGreeting = (name: string): string => {
  const prefix = `Hello, ${name}`;

  return prefix;
};

export const printGreeting = (name: string): void => {
  const greeting = buildGreeting(name);
  
};
