/**
 * Test Next.js JSON extraction from Cricbuzz scorecard
 */

import { readFileSync } from 'fs';

const html = readFileSync('../scorecard-155398.html', 'utf-8');

console.log('Analyzing Next.js JSON chunks...\n');

// Extract all Next.js data chunks
const nextDataPattern = /self\.__next_f\.push\(\[1,"([^"]+)"\]\)/g;
let match;
let chunkIndex = 0;

while ((match = nextDataPattern.exec(html)) !== null) {
  chunkIndex++;
  const jsonStr = match[1];
  
  // Check if this chunk contains scorecard-related keywords
  const hasScorecard = jsonStr.includes('innings') || 
                       jsonStr.includes('batting') || 
                       jsonStr.includes('bowling') ||
                       jsonStr.includes('batsman') ||
                       jsonStr.includes('bowler');
  
  if (hasScorecard) {
    console.log(`\n=== Chunk ${chunkIndex} (contains scorecard data) ===`);
    console.log(`Length: ${jsonStr.length} chars`);
    
    // Show a sample
    const sample = jsonStr.slice(0, 500);
    console.log(`Sample: ${sample}...`);
    
    // Try to find specific patterns
    if (jsonStr.includes('Yashasvi Jaiswal')) {
      console.log('✅ Found player: Yashasvi Jaiswal');
    }
    if (jsonStr.includes('Shubman Gill')) {
      console.log('✅ Found player: Shubman Gill');
    }
    if (jsonStr.includes('214')) {
      console.log('✅ Found score: 214');
    }
    if (jsonStr.includes('219')) {
      console.log('✅ Found score: 219');
    }
  }
}

console.log(`\n\nTotal chunks analyzed: ${chunkIndex}`);

// Also check if there's a script tag with scorecard data
console.log('\n\nLooking for script tags with scorecard data...');
const scriptPattern = /<script[^>]*>([\s\S]*?)<\/script>/gi;
let scriptMatch;
let scriptIndex = 0;

while ((scriptMatch = scriptPattern.exec(html)) !== null) {
  const scriptContent = scriptMatch[1];
  if (scriptContent.includes('innings') || scriptContent.includes('scorecard')) {
    scriptIndex++;
    console.log(`\nScript ${scriptIndex} contains scorecard keywords`);
    console.log(`Length: ${scriptContent.length} chars`);
    
    // Check for JSON data
    if (scriptContent.includes('{') && scriptContent.includes('}')) {
      console.log('Contains JSON-like structure');
    }
  }
}
